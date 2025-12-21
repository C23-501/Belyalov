LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_unsigned.ALL;
USE ieee.std_logic_arith.ALL;
LIBRARY work;
USE work.SDRAM_controller_Package.ALL;

entity Subsys_SDRAM_top is
	PORT(
		nRst : IN std_logic;
		CLK  : IN std_logic;
		nCS  : OUT    std_logic;
      nRAS : OUT    std_logic;
      nCAS : OUT    std_logic;
      nWE  : OUT    std_logic;
      CKE  : OUT    std_logic;
      DQM  : OUT    std_logic_vector (1 DOWNTO 0);
      BS   : OUT    std_logic_vector (1 DOWNTO 0);
		A    : OUT std_logic_vector(11 DOWNTO 0);
		Dq   : OUT std_logic_vector(15 DOWNTO 0);
		    -- LEDs
		LED_ctr    :  out  std_logic_vector(7 downto 0)
	);
end Subsys_SDRAM_top;

ARCHITECTURE rtl OF SubSys_SDRAM_top IS
   SIGNAL A_FSM       : std_logic_vector(11 DOWNTO 0);
   SIGNAL A_Subsys    : std_logic_vector(11 DOWNTO 0);
   SIGNAL BS_FSM      : std_logic_vector(1 DOWNTO 0);
   SIGNAL BS_Subsys   : std_logic_vector(1 DOWNTO 0);
   SIGNAL CKE_FSM     : std_logic;
   SIGNAL CKE_Subsys  : std_logic;
   SIGNAL DQM_FSM     : std_logic_vector(1 DOWNTO 0);
   SIGNAL DQM_Subsys  : std_logic_vector(1 DOWNTO 0);
   SIGNAL StateFSM    : StateFSM_type;
   SIGNAL State_out   : StateSubsys_type;
   SIGNAL nCAS_FSM    : std_logic;
   SIGNAL nCAS_Subsys : std_logic;
   SIGNAL nCS_FSM     : std_logic;
   SIGNAL nCS_Subsys  : std_logic;
   SIGNAL nRAS_FSM    : std_logic;
   SIGNAL nRAS_Subsys : std_logic;
   SIGNAL nWE_FSM     : std_logic;
   SIGNAL nWE_Subsys  : std_logic;
	signal LED_counter  :  std_logic_vector(23 downto 0);
   signal LED_quarters :  std_logic_vector(1 downto 0);
   signal LED_r        :  std_logic_vector(7 downto 0);
   signal quarter_flag :  std_logic;
	
	COMPONENT Controller_SDRAM_arbiter
   PORT (
      -- Общие
      nRst        : IN     std_logic ;
      CLK         : IN     std_logic ;
      -- От FSM
      StateFSM    : IN     StateFSM_type ;
      nCS_FSM     : IN     std_logic ;
      nRAS_FSM    : IN     std_logic ;
      nCAS_FSM    : IN     std_logic ;
      nWE_FSM     : IN     std_logic ;
      CKE_FSM     : IN     std_logic ;
      DQM_FSM     : IN     std_logic_vector (1 DOWNTO 0);
      BS_FSM      : IN     std_logic_vector (1 DOWNTO 0);
      A_FSM       : IN     std_logic_vector (11 DOWNTO 0);
      --  От подсистемы
      nCS_Subsys  : IN     std_logic ;
      nRAS_Subsys : IN     std_logic ;
      nCAS_Subsys : IN     std_logic ;
      nWE_Subsys  : IN     std_logic ;
      CKE_Subsys  : IN     std_logic ;
      DQM_Subsys  : IN     std_logic_vector (1 DOWNTO 0);
      BS_Subsys   : IN     std_logic_vector (1 DOWNTO 0);
      A_Subsys    : IN     std_logic_vector (11 DOWNTO 0);
      --  Выходы на SDRAM
      nCS         : OUT    std_logic ;
      nRAS        : OUT    std_logic ;
      nCAS        : OUT    std_logic ;
      nWE         : OUT    std_logic ;
      CKE         : OUT    std_logic ;
      DQM         : OUT    std_logic_vector (1 DOWNTO 0);
      bs          : OUT    std_logic_vector (1 DOWNTO 0);
      A           : OUT    std_logic_vector (11 DOWNTO 0)
   );
   END COMPONENT;
   COMPONENT SubSys_Controller
   GENERIC (
      Burst_length : integer := 8;
      CAS_Latency  : integer := 3;
      CLK_Freq_MHz : integer := 160
   );
   PORT (
      -- Общие
      nRst      : IN     std_logic ;
      CLK       : IN     std_logic ;
      -- Входы с FSM
      StateFSM  : IN     StateFSM_type ;
      A_FSM     : IN     std_logic_vector (11 DOWNTO 0);
      -- Выходы на арбитр
      nCS       : OUT    std_logic ;
      nRAS      : OUT    std_logic ;
      nCAS      : OUT    std_logic ;
      nWE       : OUT    std_logic ;
      CKE       : OUT    std_logic ;
      DQM       : OUT    std_logic_vector (1 DOWNTO 0);
      BS        : OUT    std_logic_vector (1 DOWNTO 0);
      A         : OUT    std_logic_vector (11 DOWNTO 0);
      State_out : OUT    StateSubsys_type 
   );
   END COMPONENT;
	
	
BEGIN
	
	StateFSM <= Waiting;
	nCS_FSM <= '1';
	nCAS_FSM <= '1';
	nRAS_FSM <= '1';
	nWE_FSM <= '1';
	CKE_FSM <= '0';
	DQM_FSM <= "00";
	A_FSM <= (others => '0');
	BS_FSM <= "00";
	
	Dq <= (others => '0');
	
	LED_ctr <= LED_r;
	
	U_2 : Controller_SDRAM_arbiter
      PORT MAP (
         nRst        => nRst,
         CLK         => CLK,
         StateFSM    => StateFSM,
         nCS_FSM     => nCS_FSM,
         nRAS_FSM    => nRAS_FSM,
         nCAS_FSM    => nCAS_FSM,
         nWE_FSM     => nWE_FSM,
         CKE_FSM     => CKE_FSM,
         DQM_FSM     => DQM_FSM,
         BS_FSM      => BS_FSM,
         A_FSM       => A_FSM,
         nCS_Subsys  => nCS_Subsys,
         nRAS_Subsys => nRAS_Subsys,
         nCAS_Subsys => nCAS_Subsys,
         nWE_Subsys  => nWE_Subsys,
         CKE_Subsys  => CKE_Subsys,
         DQM_Subsys  => DQM_Subsys,
         BS_Subsys   => BS_Subsys,
         A_Subsys    => A_Subsys,
         nCS         => nCS,
         nRAS        => nRAS,
         nCAS        => nCAS,
         nWE         => nWE,
         CKE         => CKE,
         DQM         => DQM,
         bs          => BS,
         A           => A
      );
		
		U_0 : SubSys_Controller
      GENERIC MAP (
         Burst_length => 8,
         CAS_Latency  => 3,
         CLK_Freq_MHz => 160
      )
      PORT MAP (
         nRst      => nRst,
         CLK       => CLK,
         StateFSM  => StateFSM,
         A_FSM     => A_FSM,
         nCS       => nCS_Subsys,
         nRAS      => nRAS_Subsys,
         nCAS      => nCAS_Subsys,
         nWE       => nWE_Subsys,
         CKE       => CKE_Subsys,
         DQM       => DQM_Subsys,
         bs        => BS_Subsys,
         A         => A_Subsys,
         State_out => State_out
      );
		
  LED_process : process (nRst, CLK) is
  begin
    if (nRst = '0') then
      LED_counter <= (others => '0');
      LED_quarters <= (others => '1');
      LED_r <= (others => '0');
      quarter_flag <= '0';
    elsif (rising_edge(CLK)) then
      --  LED_counter
      if (LED_counter = conv_std_logic_vector(0, LED_counter'length)) then
        LED_counter <= conv_std_logic_vector(2400000, LED_counter'length);
      else
        LED_counter <= LED_counter - '1';
      end if;
      --  quater_flag
      if (LED_counter = conv_std_logic_vector(0, LED_counter'length)) then
        if (LED_quarters = conv_std_logic_vector(0, LED_quarters'length) or LED_quarters = conv_std_logic_vector(3, LED_quarters'length)) then
          quarter_flag <= not quarter_flag;
        end if;
      end if;
      --  LED_quarters
      if (LED_counter = conv_std_logic_vector(0, LED_counter'length)) then
        if (LED_quarters = conv_std_logic_vector(0, LED_quarters'length)) then
            LED_quarters <= conv_std_logic_vector(1, LED_quarters'length);
        elsif (LED_quarters = conv_std_logic_vector(3, LED_quarters'length)) then
           LED_quarters <= conv_std_logic_vector(2, LED_quarters'length);
        else
          if (quarter_flag = '0') then
            LED_quarters <= LED_quarters + '1';
          else
            LED_quarters <= LED_quarters - '1';
          end if;
        end if;
      end if;
      --  LED_r
      if (LED_quarters = conv_std_logic_vector(0, LED_quarters'length)) then
        LED_r(1 downto 0) <= (others => '1');
        LED_r(7 downto 2) <= (others => '0');
      elsif (LED_quarters = conv_std_logic_vector(1, LED_quarters'length)) then
        LED_r(1 downto 0) <= (others => '0');
        LED_r(3 downto 2) <= (others => '1');
        LED_r(7 downto 4) <= (others => '0');
      elsif (LED_quarters = conv_std_logic_vector(2, LED_quarters'length)) then
        LED_r(3 downto 0) <= (others => '0');
        LED_r(5 downto 4) <= (others => '1');
        LED_r(7 downto 6) <= (others => '0');
      else
        LED_r(5 downto 0) <= (others => '0');
        LED_r(7 downto 6) <= (others => '1');
      end if;
    end if;
  end process;
	
END ARCHITECTURE rtl;
