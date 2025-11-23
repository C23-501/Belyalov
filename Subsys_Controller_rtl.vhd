LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_unsigned.ALL;
USE ieee.std_logic_arith.all;
LIBRARY Controller_of_engine_lib;
USE Controller_of_engine_lib.My_Package.ALL;

ENTITY SubSys_Controller IS
  GENERIC( 
      Burst_length : integer := 8;
      CAS_Latency : integer := 3
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
  signal State           : StateSubsys_type := Idle;
  signal PrevStateFSM    :  StateFSM_type;
  
  -- out
  signal nCS_r           :  std_logic;
  signal nRAS_r          :  std_logic;
  signal nCAS_r          :  std_logic;
  signal nWE_r           :  std_logic;
  signal CKE_r           :  std_logic;
  signal DQM_r           :  std_logic;
  signal BS_r            :  std_logic_vector(1 downto 0);
  signal A_r             :  std_logic_vector(11 downto 0);
  
  -- refresh
  signal Ref_time_counter   :  std_logic_vector(11 downto 0);
  signal Ref_clk_counter    :  std_logic_vector(3 downto 0);
  
  -- precharge
  signal PrechargeDone_flag :  std_logic;
  signal PrechargetoActive_counter : std_logic_vector(1 downto 0);
  
  -- Инициализация SDRAM
  constant INIT_COUNTER_MAX : std_logic_vector(15 downto 0) := conv_std_logic_vector(33200, 16);
  signal Init_counter : std_logic_vector(15 downto 0);
  signal MRSet_counter : std_logic_vector(1 downto 0);
  signal Ref_cycles_counter : std_logic_vector(2 downto 0);

  -- Mode Register value (A[11:0]) для команды Load Mode Register
  signal MR_value : std_logic_vector(11 downto 0);
  --
BEGIN
  --  Проверка generic
  assert (Burst_length = 1 or Burst_length = 2 or Burst_length = 4 or Burst_length = 8 or Burst_length = 16)
    report "Burst length must be equal 1, 2, 4, 8 or 16 (full page)" severity error;

  assert (CAS_Latency = 2 or CAS_Latency = 3)
    report "CAS_Latency must be equal 2 or 3" severity error;
  --
  nCS <= nCS_r;
  nRAS <= nRAS_r;
  nCAS <= nCAS_r;
  nWE <= nWE_r;
  CKE <= CKE_r;
  DQM <= DQM_r;
  BS <= BS_r;
  A <= A_r;
  State_out <= State;
  --
  --------------------------------------------------------------------
  -- Формирование Mode Register (MR_value) из Burst_length и CAS_Latency
  --------------------------------------------------------------------
  ModeReg: process(nRst) is
  begin

    -- Burst Length: A[2:0]
    case Burst_length is
      when 1  => MR_value(2 downto 0) <= "000";
      when 2  => MR_value(2 downto 0) <= "001";
      when 4  => MR_value(2 downto 0) <= "010";
      when 8  => MR_value(2 downto 0) <= "011";
      when 16 => MR_value(2 downto 0) <= "111";
      when others => MR_value(2 downto 0) <= "000";
    end case;

    -- Burst Type: A[3] = 0 (sequential)
    MR_value(3) <= '0';

    -- CAS Latency: A[6:4]
    case CAS_Latency is
      when 2 =>
        MR_value(6 downto 4) <= "010";
      when 3 =>
        MR_value(6 downto 4) <= "011";
      when others =>
        MR_value(6 downto 4) <= "000";
    end case;

    -- Write Mode (burst read, burst write)
    MR_value(9) <= '0';

    -- Reserved
    MR_value(8 downto 7) <= (others => '0');
    MR_value(11 downto 10) <= (others => '0');
  end process;

  --------------------------------------------------------------------
  -- FSM подсистемы: Idle / Refresh / Initialisation / Precharge
  --------------------------------------------------------------------
  
  States: process(nRst, CLK) is
  begin
    if (nRst = '0') then
      State <= Initialisation;
    elsif (rising_edge(CLK)) then
      case State is
        when Idle =>
          if (Ref_time_counter = conv_std_logic_vector(0, Ref_time_counter'length)) then  -- Refresh
            State <= Refresh;
          elsif (PrechargeDone_flag = '0') then   -- Precharge
            if ((PrevStateFSM = Reading or PrevStateFSM = Writing) and StateFSM /= PrevStateFSM) then
              State <= Precharge;
            end if;
          end if;
        when Refresh =>
          if (Ref_clk_counter = conv_std_logic_vector(0, Ref_clk_counter'length)) then
            State <= Idle;
          end if;
        when Initialisation =>
          if (Ref_cycles_counter = conv_std_logic_vector(0, Ref_cycles_counter'length) and Ref_clk_counter = conv_std_logic_vector(0, Ref_clk_counter'length)) then -- Initialisation
            State <= Idle;
	  end if;
        when Precharge =>
          if (StateFSM = Precharge and PrechargetoActive_counter = conv_std_logic_vector(0, PrechargetoActive_counter'length)) then
            State <= Idle;
          end if;
        when others =>
          State <= Idle;
      end case;
    end if;
  end process;

  --------------------------------------------------------------------
  -- Основная логика: инициализация / refresh / precharge
  --------------------------------------------------------------------
  
  Main_logic: process(nRst, CLK) is
  begin
    if (nRst = '0') then
      -- регистры выходов
      nCS_r <= '0';
      nRAS_r <= '0';
      nCAS_r <= '0';
      nWE_r <= '0';
      CKE_r <= '0';
      BS_r <= (others => '0');
      A_r <= (others => '0');
      -- внутренняя логика
      Init_counter <= INIT_COUNTER_MAX;
    elsif (rising_edge(CLK)) then
      PrevStateFSM <= StateFSM;
------------------------------------------------------------------------------------------------------------- Выходные сигналы

       --  nCS_r
      if (StateFSM = Refresh) then
        if (PrechargeDone_flag = '1') then    -- Precharge уже сделан, делаем Refresh
          if (Ref_clk_counter = conv_std_logic_vector(10, Ref_clk_counter'length)) then
            nCS_r <= '0';
          else
            nCS_r <= '1';
          end if;
        elsif (PrechargetoActive_counter = conv_std_logic_vector(3, PrechargetoActive_counter'length)) then    --  Precharge перед Refresh не было, делаем
          nCS_r <= '0';
        else
          nCS_r <= '1';
        end if;
      elsif (StateFSM = Initialisation) then
        if (PrechargetoActive_counter = conv_std_logic_vector(3, PrechargetoActive_counter'length)) then     -- Precharge перед MR_set
          nCS_r <= '0';
        elsif (PrechargeDone_flag = '1' and MRSet_counter = conv_std_logic_vector(2, MRSet_counter'length)) then   -- MR Set
          nCS_r <= '0';
        elsif (Init_counter /= conv_std_logic_vector(0, Init_counter'length)) then  --NoOp при ожидании
          nCS_r <= '0';
        elsif (Ref_clk_counter = conv_std_logic_vector(10, Ref_clk_counter'length) and MRSet_counter = conv_std_logic_vector(0, MRSet_counter'length)) then  -- Refresh после MR set
          nCS_r <= '0';
        else
          nCS_r <= '1';
        end if;
      elsif (StateFSM = Precharge and PrechargetoActive_counter = conv_std_logic_vector(3, PrechargetoActive_counter'length)) then  -- Precharge
        nCS_r <= '0';
      else
        nCS_r <= '1';
      end if;
      --  nRAS_r
      if (StateFSM = Refresh) then
        if (PrechargeDone_flag = '1') then    -- Precharge уже сделан, делаем Refresh
          if (Ref_clk_counter = conv_std_logic_vector(10, Ref_clk_counter'length)) then
            nRAS_r <= '0';
          end if;
        elsif (PrechargetoActive_counter = conv_std_logic_vector(3, PrechargetoActive_counter'length)) then    --  Precharge перед Refresh не было, делаем
          nRAS_r <= '0';
        else
          nRAS_r <= '1';
        end if;
      elsif (StateFSM = Precharge and PrechargetoActive_counter = conv_std_logic_vector(3, PrechargetoActive_counter'length)) then  -- Precharge
        nRAS_r <= '0';
      elsif (StateFSM = Initialisation) then
        if (Init_counter /= conv_std_logic_vector(0, Init_counter'length)) then   --NoOp при ожидании
          nRAS_r <= '1';
        else                                                                      --Всё остальное
          nRAS_r <= '0';
        end if;
      else
        nRAS_r <= '1';
      end if;
      --  nCAS_r
      if (StateFSM = Refresh) then
        if (PrechargeDone_flag = '1') then    -- Precharge уже сделан, делаем Refresh
          nCAS_r <= '0';
        elsif (PrechargetoActive_counter = conv_std_logic_vector(3, PrechargetoActive_counter'length)) then    -- Precharge перед Refresh не было, делаем
          nCAS_r <= '1';
        end if;
      elsif (StateFSM = Precharge and PrechargetoActive_counter = conv_std_logic_vector(3, PrechargetoActive_counter'length)) then  -- Precharge
        nCAS_r <= '1';
      elsif (StateFSM = Initialisation) then
        if (PrechargetoActive_counter /= conv_std_logic_vector(0, PrechargetoActive_counter'length)) then       -- Ожидание и precharge
          nCAS_r <= '1';
        else                                                                                                    -- MR set и refresh
          nCAS_r <= '0';
        end if;
      else
        nCAS_r <= '1';
      end if;
      --  nWE_r
      if (StateFSM = Refresh) then
        if (PrechargeDone_flag = '1') then    -- Precharge уже сделан, делаем Refresh
          nWE_r <= '0';
        elsif (PrechargetoActive_counter = conv_std_logic_vector(3, PrechargetoActive_counter'length)) then    -- Precharge перед Refresh не было, делаем
          nWE_r <= '0';
        end if;
      elsif (StateFSM = Precharge and PrechargetoActive_counter = conv_std_logic_vector(3, PrechargetoActive_counter'length)) then  -- Precharge
        nWE_r <= '0';
      elsif (StateFSM = Initialisation) then
        if (Init_counter = conv_std_logic_vector(0, Init_counter'length) and MRSet_counter /= conv_std_logic_vector(0, MRSet_counter'length)) then  -- Precharge и MR set
          nWE_r <= '0';
        else                                                                                                                                -- NoOp при ожидании и refresh
          nWE_r <= '1';
        end if;
      else
        nWE_r <= '1';
      end if;
      --  A_r
      if (StateFSM = Precharge and PrechargetoActive_counter = conv_std_logic_vector(3, PrechargetoActive_counter'length)) then
        A(9 downto 0) <= (others => '0');
        A(10) <= '1';
        A(11) <= '0';
      elsif (Init_counter = conv_std_logic_vector(0, Init_counter'length)) then
        A_r <= MR_value;
      else
        A <= (others => '0');
      end if;
      --  BS_r
      BS_r <= (others => '0');
      --  CKE_r
      CKE_r <= '1';
      --  DQM_r
      DQM_r <= '1';
      
------------------------------------------------------------------------------------------------------------- Флаги

      --  PrechargeDone_flag  (флаг, показывающий, был ли сделан precharge)
      if ((StateFSM = Reading and PrevStateFSM /= Reading) or (StateFSM = Writing and PrevStateFSM /= Writing)) then   -- Чтение или запись с autoprecharge
        if (A_FSM(10) = '1') then
          PrechargeDone_flag <= '1';
        end if;
      elsif (StateFSM = Precharge) then   --  Precharge
        PrechargeDone_flag <= '1';
      elsif ((StateFSM = Refresh or StateFSM = Initialisation) and PrechargetoActive_counter = conv_std_logic_vector(0, PrechargetoActive_counter'length)) then   -- Precharge перед Refresh
        PrechargeDone_flag <= '1';                                                                                                                         -- или записью в Mode Register
      elsif (StateFSM = Activation) then
        PrechargeDone_flag <= '0';
      end if;
      
------------------------------------------------------------------------------------------------------------- Счётчики
      --  Ref_time_counter (счётчик времени до следующего цикла auto-refresh - 64 мс / 4096)
      if (StateFSM /= Refresh) then
        if (Ref_time_counter /= conv_std_logic_vector(0, Ref_time_counter'length)) then
          Ref_time_counter <= Ref_time_counter + '1';
        end if;
      else
        Ref_time_counter <= conv_std_logic_vector(2604, Ref_time_counter'length);
      end if;
      --  Ref_clk_counter  (счётчик тактов цикла auto-refresh - tRC)
      if (StateFSM = Refresh or (MRSet_counter = conv_std_logic_vector(0, MRSet_counter'length) and Ref_cycles_counter /= conv_std_logic_vector(0, Ref_cycles_counter'length))) then
        if (Ref_clk_counter = conv_std_logic_vector(0, Ref_clk_counter'length)) then
          Ref_clk_counter <= conv_std_logic_vector(10, Ref_clk_counter'length);
        else
          Ref_clk_counter <= Ref_clk_counter - '1';
        end if;
      else
        Ref_clk_counter <= conv_std_logic_vector(10, Ref_clk_counter'length);
      end if;
      --  Ref_cycles_counter  (счётчик циклов auto-refresh после установки Mode Register)
      if (MRSet_counter = conv_std_logic_vector(0, MRSet_counter'length)) then
        if (Ref_cycles_counter /= conv_std_logic_vector(0, Ref_cycles_counter'length)) then
          Ref_cycles_counter <= Ref_cycles_counter - '1';
        end if;
      else
        Ref_cycles_counter <= conv_std_logic_vector(8, Ref_cycles_counter'length);
      end if;
      --  PrechargetoActive_clock  (счётчик времени от precharge до active - tRP)
      if (PrechargetoActive_counter /= conv_std_logic_vector(0, PrechargetoActive_counter'length)) then
        if (StateFSM = Precharge) then
          PrechargetoActive_counter <= PrechargetoActive_counter - '1';
        elsif (StateFSM = Refresh and PrechargeDone_flag = '0') then
          PrechargetoActive_counter <= PrechargetoActive_counter - '1';
        elsif (StateFSM = Initialisation and Init_counter = conv_std_logic_vector(0, Init_counter'length)) then
          PrechargetoActive_counter <= PrechargetoActive_counter - '1';
        else
          PrechargetoActive_counter <= conv_std_logic_vector(3, PrechargetoActive_counter'length);
        end if;
      elsif (StateFSM /= PrevStateFSM) then
        PrechargetoActive_counter <= conv_std_logic_vector(3, PrechargetoActive_counter'length);
      end if;
      --  Init_counter  (счётчик времени от сброса до начала инициализации памяти - 200 мкс)
      if (StateFSM = Initialisation) then
        if (Init_counter /= conv_std_logic_vector(0, Init_counter'length)) then
          Init_counter <= Init_counter - '1';
        end if;
      else
        Init_counter <= INIT_COUNTER_MAX;
      end if;
      -- MRSet_counter  (счётчик времени между MR set и другой командой - tRSC)
      if (StateFSM = Initialisation) then
        if (PrechargeDone_flag = '1' and MRSet_counter /= conv_std_logic_vector(0, MRSet_counter'length)) then
          MRSet_counter <= MRSet_counter - '1';
        end if;
      else
        MRSet_counter <= conv_std_logic_vector(2, MRSet_counter'length);
      end if;
    end if;
  end process;
END ARCHITECTURE rtl;
