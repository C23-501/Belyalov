LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_arith.all;
USE ieee.std_logic_unsigned.ALL;
use ieee.numeric_std.all;

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
  signal SerDataOut_r : std_logic_vector(7 downto 0);
  signal DesDataOut_r : std_logic_vector(7 downto 0);
  signal SerCounter_r : std_logic_vector(2 downto 0);
  signal DesCounter_r : std_logic_vector(2 downto 0);
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
      DesDataOut_r <= (others => '0');
      SerCounter_r <= (others => '0');
      DesCounter_r <= (others => '0');
    elsif (rising_edge(CLK)) then
    --  SerDataOut_r
      if (SerCounter_r = "000") then
        SerDataOut_r <= SerDataIn;
      elsif (SerEn = '1') then
        for i in 0 to 6 loop
          SerDataOut_r(i + 1)<= SerDataOut_r(i);
        end loop;
      end if;
    --  SerCounter_r
      if (SerEn = '1') then
        SerCounter_r <= SerCounter_r + '1';
      else
        SerCounter_r <= (others => '0');
      end if;
    --  DesDataOut_r
      if (DesEn = '1') then
        DesDataOut_r(0) <= DesDataIn;
        for i in 0 to 6 loop
          DesDataOut_r(i + 1) <= DesDataOut_r(i);
        end loop;
      end if;
    --  DesCounter_r
      if (DesEn = '0') then
        DesCounter_r <= (others => '0');
      else
        DesCounter_r <= DesCounter_r + '1';
      end if;
    --  DesSTB
      if (DesCounter_r = "111") then
        DesSTB <= '1';
      else
        DesSTB <= '0';
      end if;
    end if;
  end process;
END ARCHITECTURE rtl;

