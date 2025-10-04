LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_unsigned.ALL;
USE ieee.std_logic_arith.all;

ENTITY SerDes_8 IS
  PORT (
    nRst       :  in   std_logic;
    CLK        :  in   std_logic;
    SerEn      :  in   std_logic;
    SerDataIn  :  in   std_logic_vector(7 downto 0);
    SerDataOut :  out  std_logic;
    DesEn      :  in   std_logic;
    DesDataIn  :  in   std_logic;
    DesDataOut :  out  std_logic_vector(7 downto 0);
    DesSTB     :  out  std_logic
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
BEGIN
  --
  SerDataOut <= SerDataOut_r(7);
  DesDataOut <= DesDataOut_r;
  --
  process (nRst, CLK) is
  begin
    if (nRst = '0') then
      SerDataOut_r <= (others => '0');
      DesCounter <= conv_std_logic_vector(7, DesCounter'length);
      SerCounter <= conv_std_logic_vector(7, SerCounter'length);
      DesDataOut_r <= (others => '0');
      DesShift_r <= (others => '0');
      DesSTB <= '0';
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
END ARCHITECTURE rtl;
