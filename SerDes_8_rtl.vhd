LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_unsigned.ALL;
USE ieee.std_logic_arith.all;

ENTITY SerDes_8 IS
  PORT (
    -- SerDes
    nRst       :  in   std_logic;
    CLK        :  in   std_logic;
    SerEn      :  in   std_logic;
    SerDataIn  :  in   std_logic_vector(7 downto 0);
    SerDataOut :  out  std_logic;
    DesEn      :  in   std_logic;
    DesDataIn  :  in   std_logic;
    DesDataOut :  out  std_logic_vector(7 downto 0);
    DesSTB     :  out  std_logic;
    -- LEDs
    LED_ctr    :  out  std_logic_vector(7 downto 0)
  );
END ENTITY SerDes_8;

--
ARCHITECTURE rtl OF SerDes_8 IS
  --
  signal SerEn_r      :  std_logic;
  signal DesEn_r      :  std_logic;
  signal SerDataOut_r :  std_logic_vector(7 downto 0);
  signal DesDataOut_r :  std_logic_vector(7 downto 0);
  signal DesShift_r   :  std_logic_vector(7 downto 0);
  signal SerCounter   :  std_logic_vector(2 downto 0);
  signal DesCounter   :  std_logic_vector(2 downto 0);
  --
  signal LED_counter  :  std_logic_vector(23 downto 0);
  signal LED_quarters :  std_logic_vector(1 downto 0);
  signal LED_r        :  std_logic_vector(7 downto 0);
  signal quarter_flag :  std_logic;
  --
BEGIN
  --
  SerDataOut <= SerDataOut_r(7);
  DesDataOut <= DesDataOut_r;
  LED_ctr <= LED_r;
  --
  process (nRst, CLK) is
  begin
    if (nRst = '0') then
      SerDataOut_r <= (others => '0');
      --DesCounter <= conv_std_logic_vector(7, DesCounter'length);
      --SerCounter <= conv_std_logic_vector(7, SerCounter'length);
		DesCounter <= (others => '0');
      SerCounter <= (others => '0');
      DesDataOut_r <= (others => '0');
      DesShift_r <= (others => '0');
      DesSTB <= '0';
		SerEn_r <= '0';
      DesEn_r <= '0';
     elsif (rising_edge(CLK)) then
      SerEn_r <= SerEn;
      DesEn_r <= DesEn;
      if (DesCounter = conv_std_logic_vector(0, DesCounter'length)) then
        DesDataOut_r <= DesShift_r;
      end if;
    --  SerDataOut_r
      if (SerEn = '1') then
        if (SerCounter = conv_std_logic_vector(0, SerCounter'length) or (SerEn = '1' and SerEn_r = '0')) then
          SerDataOut_r <= SerDataIn;
        else
          for i in 0 to 6 loop
            SerDataOut_r(i + 1) <= SerDataOut_r(i);
          end loop;
        end if;
      end if;
    --  SerCounter
      if (SerEn = '0') then
        SerCounter <= conv_std_logic_vector(7, SerCounter'length);
      else
        if (SerCounter = conv_std_logic_vector(0, SerCounter'length)) then
          SerCounter <= conv_std_logic_vector(7, SerCounter'length);
        elsif (SerEn = '1' and SerEn_r = '1') then
          SerCounter <= SerCounter - '1';
        end if;
      end if;
    --  DesShift_r
      if (DesEn = '1') then
        DesShift_r(0) <= DesDataIn;
        for i in 0 to 6 loop
          DesShift_r(i + 1) <= DesShift_r(i);
        end loop;
      end if;
    --  DesCounter
      if (DesEn = '0') then
        DesCounter <= conv_std_logic_vector(7, DesCounter'length);
      else
        if (DesCounter = conv_std_logic_vector(0, DesCounter'length)) then
          DesCounter <= conv_std_logic_vector(7, DesCounter'length);
        elsif (DesEn = '1' and DesEn_r = '1') then
          DesCounter <= DesCounter - '1';
        end if;
      end if;
    --  DesSTB
      if (DesCounter = conv_std_logic_vector(0, DesCounter'length)) then
        DesSTB <= '1';
      else
        DesSTB <= '0';
      end if;
    end if;
  end process;
  --
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
