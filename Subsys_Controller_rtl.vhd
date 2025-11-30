LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_unsigned.ALL;
USE ieee.std_logic_arith.ALL;
USE ieee.numeric_std.ALL;
USE ieee.math_real.ALL;
LIBRARY Controller_of_engine_lib;
USE Controller_of_engine_lib.My_Package.ALL;

ENTITY SubSys_Controller IS
  GENERIC( 
      Burst_length : integer := 8;
      CAS_Latency : integer := 3;
      CLK_Freq_MHz : integer := 160
  );
  
  PORT(
    -- Общие
    nRst : in std_logic;
    CLK  : in std_logic;
    -- Входы с FSM
    StateFSM : in StateFSM_type;
    BS_FSM   : in std_logic_vector(1 downto 0);
    A_FSM    : in std_logic_vector(11 downto 0);
    -- Выходы на арбитр
    nCS         : out std_logic;
    nRAS        : out std_logic;
    nCAS        : out std_logic;
    nWE         : out std_logic;
    CKE         : out std_logic;
    DQM         : out std_logic;
    BS          : out std_logic_vector(1 downto 0);
    A           : out std_logic_vector(11 downto 0);
    State_out   : out StateSubsys_type
  );
END ENTITY SubSys_Controller;

--
ARCHITECTURE rtl OF SubSys_Controller IS
  
  -- state
  signal State           :  StateSubsys_type := Idle;
  signal PrevState       :  StateSubsys_type;
  signal PrevStateFSM    :  StateFSM_type;
  
  -- out
  signal nCS_s           :  std_logic;
  signal nRAS_s          :  std_logic;
  signal nCAS_s          :  std_logic;
  signal nWE_s           :  std_logic;
  signal CKE_s           :  std_logic;
  signal DQM_s           :  std_logic;
  signal BS_s            :  std_logic_vector(1 downto 0);
  signal A_s             :  std_logic_vector(11 downto 0);

  constant CLK_PRD_ns : real := 1000.0 / real(CLK_Freq_MHz);
  constant REF_TIME : integer := integer(64_000_000.0 / (4096.0 * CLK_PRD_ns));
  constant INIT_COUNTER_MAX : integer := integer(200_000.0 / CLK_PRD_ns);

  signal CSRefChange_flag : std_logic;
  
  -- refresh
  signal Ref_time_counter   :  std_logic_vector(integer(floor(log2(real(REF_TIME)))) downto 0);
  signal Ref_clk_counter    :  std_logic_vector(2 downto 0);
  
  -- precharge
  signal PrechargeDone_flag :  std_logic;
  signal PrechargetoActive_counter : std_logic_vector(1 downto 0);
  
  -- Инициализация SDRAM
  signal Init_counter : std_logic_vector(integer(floor(log2(real(INIT_COUNTER_MAX)))) downto 0);
  signal MRSet_counter : std_logic_vector(1 downto 0);
  signal Ref_cycles_counter : std_logic_vector(2 downto 0);
  signal MRSetDone : std_logic;

  -- Mode Register value (A[11:0]) для команды Load Mode Register
  signal MR_value : std_logic_vector(11 downto 0);
  --
BEGIN
  --  Проверка generic
  assert (Burst_length = 1 or Burst_length = 2 or Burst_length = 4 or Burst_length = 8 or Burst_length = 16)
    report "Burst length must be equal 1, 2, 4, 8 or 16 (full page)" severity error;

  assert (CAS_Latency = 2 or CAS_Latency = 3)
    report "CAS_Latency must be equal 2 or 3" severity error;

  assert (CLK_Freq_MHz > 0)
    report "CLK_Freq_MHz must be positive" severity error;
  --
  --
  nCS <= nCS_s;
  nRAS <= nRAS_s;
  nCAS <= nCAS_s;
  nWE <= nWE_s;
  CKE <= CKE_s;
  DQM <= DQM_s;
  BS <= BS_s;
  A <= A_s;
  State_out <= State;
  --
  -------------------  Mode Register ----------------------------
  -- Burst Length
  MR_value(2 downto 0) <= "000" when burst_length = 1 else
                          "001" when burst_length = 2 else
                          "010" when burst_length = 4 else
                          "011" when burst_length = 8 else
                          "111" when burst_length = 256 else
                          "000";

  -- Addressing mode (Sequential)
  MR_value(3) <= '0';

  -- CAS Latency
  MR_value(6 downto 4) <= "010" when cas_latency = 2 else
                          "011" when cas_latency = 3 else
                          "000";

  -- Write mode (Burst read and burst write)
  MR_value(9) <= '0';

  -- Reserved
  MR_value(8 downto 7)   <= "00";
  MR_value(11 downto 10) <= "00";

  ---------------------------------------------------------------

  States : process(nRst, CLK)
  begin
    if (nRst = '0') then
      State <= Idle;
    elsif rising_edge(CLK) then
      case State is
        
            ----------------------------------------------------------------------
            -- IDLE
            ----------------------------------------------------------------------
            when Idle =>
                -- Переход в Ctr_request, когда Init_counter = 0
                if Init_counter = conv_std_logic_vector(0, Init_counter'length) then
                    State <= Ctr_request;
                else
                    State <= Idle;
                end if;

            ----------------------------------------------------------------------
            -- Ctr_request
            ----------------------------------------------------------------------
            when Ctr_request =>
                -- Переход возможен только когда StateFSM = Waiting
                if StateFSM = Waiting then
                    -- Precharge
                    if (PrechargeDone_flag = '0' or MRSetDone = '0') then
                        State <= Precharge;
                    -- Refresh
                    elsif (PrechargeDone_flag = '1' and Ref_time_counter = conv_std_logic_vector(0, Ref_time_counter'length)) then
                        State <= Refresh;
                    else
                        State <= Ctr_request;
                    end if;
                else
                    State <= Ctr_request;
                end if;

            ----------------------------------------------------------------------
            -- Precharge
            ----------------------------------------------------------------------
            when Precharge =>
                -- Переход только при PrechargeActive_clock = 0
                if PrechargetoActive_counter = conv_std_logic_vector(0, PrechargetoActive_counter'length) then
                    -- SetMR
                    if MRSetDone = '0' then
                        State <= SetMR;
                    -- Refresh
                    elsif Ref_time_counter = conv_std_logic_vector(0, Ref_time_counter'length) then
                        State <= Refresh;
                    else
                        State <= ValidOP;
                    end if;
                else
                    State <= Precharge;
                end if;

            ----------------------------------------------------------------------
            -- SetMR
            ----------------------------------------------------------------------
            when SetMR =>
                -- SetMR -> Refresh если MRSet_counter = 0
                if MRSet_counter = conv_std_logic_vector(0, MRSet_counter'length) then
                    State <= Refresh;
                else
                    State <= SetMR;
                end if;

            ----------------------------------------------------------------------
            -- Refresh
            ----------------------------------------------------------------------
            when Refresh =>
                -- Refresh -> ValidOp
                if Ref_cycles_counter = conv_std_logic_vector(0, Ref_cycles_counter'length) and
                   Ref_clk_counter  = conv_std_logic_vector(0, Ref_clk_counter'length) then
                    State <= ValidOp;
                else
                    State <= Refresh;
                end if;

            ----------------------------------------------------------------------
            -- ValidOp
            ----------------------------------------------------------------------
            when ValidOp =>
                -- ValidOp -> Ctr_request
                if (Ref_time_counter = conv_std_logic_vector(0, Ref_time_counter'length)) or
                   ((StateFSM /= PrevStateFSM) and
                    (PrevStateFSM = Reading or PrevStateFSM = Writing) and
                    PrechargeDone_flag = '0') then
                    State <= Ctr_request;
                else
                    State <= ValidOp;
                end if;

            when others =>
                State <= Idle;

        end case;
    end if;
end process;
  
  --------------------------------------------------------------------
  -- Основная логика: инициализация / refresh / precharge
  --------------------------------------------------------------------
  
  Main_synch_logic: process(nRst, CLK) is
    
  begin
    if (nRst = '0') then
      -- внутренняя логика
      Init_counter <= conv_std_logic_vector(INIT_COUNTER_MAX, Init_counter'length);
      MRSetDone <= '0';
    elsif (rising_edge(CLK)) then
      PrevStateFSM <= StateFSM;
      PrevState <= State;
      
------------------------------------------------------------------------------------------------------------- Флаги

      --  PrechargeDone_flag  (флаг, показывающий, был ли сделан precharge)
      if ((StateFSM = Reading and PrevStateFSM /= Reading) or (StateFSM = Writing and PrevStateFSM /= Writing)) then   -- Чтение или запись с autoprecharge
        if (A_FSM(10) = '1') then
          PrechargeDone_flag <= '1';
        end if;
      elsif (State = Precharge) then   --  Precharge
        PrechargeDone_flag <= '1';
      elsif (StateFSM = Activation) then
        PrechargeDone_flag <= '0';
      end if;
      --  CSRefChange_flag
      if (Ref_clk_counter = conv_std_logic_vector(0, Ref_clk_counter'length)) then
        CSRefChange_flag <= '1';
      else
        CSRefChange_flag <= '0';
      end if;
      --  MRSetDone
      if (MRSet_counter = conv_std_logic_vector(0, MRSet_counter'length)) then
        MRSetDone <= '1';
      end if;
      
------------------------------------------------------------------------------------------------------------- Счётчики
      --  Ref_time_counter (счётчик времени до следующего цикла auto-refresh - 64 мс / 4096)
      if (State /= Refresh) then
        if (Ref_time_counter /= conv_std_logic_vector(0, Ref_time_counter'length)) then
          Ref_time_counter <= Ref_time_counter + '1';
        end if;
      else
        Ref_time_counter <= conv_std_logic_vector(REF_TIME, Ref_time_counter'length);
      end if;
      --  Ref_clk_counter  (счётчик тактов цикла auto-refresh - tRC)
      if (State = Refresh) then
        if (Ref_clk_counter = conv_std_logic_vector(0, Ref_clk_counter'length)) then
          Ref_clk_counter <= conv_std_logic_vector(9, Ref_clk_counter'length);
        else
          Ref_clk_counter <= Ref_clk_counter - '1';
        end if;
      else
        Ref_clk_counter <= conv_std_logic_vector(9, Ref_clk_counter'length);
      end if;
      --  Ref_cycles_counter  (счётчик циклов auto-refresh после установки Mode Register)
      if (State = Refresh and Ref_clk_counter = conv_std_logic_vector(0, Ref_clk_counter'length)) then
        Ref_cycles_counter <= Ref_cycles_counter - '1';
      elsif (State = SetMR) then
        Ref_cycles_counter <= conv_std_logic_vector(7, Ref_cycles_counter'length);
      else
        Ref_cycles_counter <= conv_std_logic_vector(0, Ref_cycles_counter'length);
      end if;
      --  PrechargetoActive_clock  (счётчик времени от precharge до active - tRP)
      if (State = Precharge) then
        PrechargetoActive_counter <= PrechargetoActive_counter - '1';
      else
        PrechargetoActive_counter <= conv_std_logic_vector(2, PrechargetoActive_counter'length);
      end if;
      --  Init_counter  (счётчик времени от сброса до начала инициализации памяти - 200 мкс)
      if (State = Idle) then
        Init_counter <= Init_counter - '1';
      else
        Init_counter <= conv_std_logic_vector(INIT_COUNTER_MAX, Init_counter'length);
      end if;
      -- MRSet_counter  (счётчик времени между MR set и другой командой - tRSC)
      if (State = SetMR) then
        MRSet_counter <= MRSet_counter - '1';
      else
        MRSet_counter <= conv_std_logic_vector(1, MRSet_counter'length);
      end if;
    end if;
  end process;

  Main_scheme_logic : process(State, PrevState, CSRefChange_flag, nCS_s, nRAS_s, nCAS_s, nWE_s, A_s, BS_s, CKE_s, DQM_s) is
  begin
    -- nCS_s
    if ((State /= PrevState and State /= Idle and State /= ValidOp) or CSRefChange_flag = '1') then
      nCS_s <= '0';
    else
      nCS_s <= '1';
    end if;
    -- nRAS_s
    if (State = Precharge or State = Refresh or State = SetMR) then
      nRAS_s <= '0';
    else
      nRAS_s <= '1';
    end if;
    -- nCAS_s
    if (State = SetMR or State = Refresh) then
      nCAS_s <= '0';
    else
      nCAS_s <= '1';
    end if;
    -- nWE_s
    if (State = SetMR or State = Precharge) then
      nWE_s <= '0';
    else
      nWE_s <= '1';
    end if;
    -- A_s
    if (State = SetMR) then
      A_s <= MR_value;
    else
      A_s(9 downto 0) <= (others => '0');
      A_s(10) <= '1';
      A_s(11) <= '0';
    end if;
    --BS_s
    BS_s <= (others => '0');
    -- CKE_s
    CKE_s <= '1';
    -- DQM_s
    DQM_s <= '1';
    
  end process;
END ARCHITECTURE rtl;
