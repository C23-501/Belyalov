LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.std_logic_unsigned.ALL;

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
  signal SerCounter   : std_logic_vector(2 downto 0);
  signal DesCounter   : std_logic_vector(2 downto 0);
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
      SerCounter <= (others => '0');
      DesCounter <= (others => '1');
    elsif (rising_edge(CLK)) then
    --  SerDataOut_r
      if (SerEn = '1') then
        if (SerCounter = "000") then
          SerDataOut_r <= SerDataIn;
        else
          for i in 0 to 6 loop
            SerDataOut_r(i + 1) <= SerDataOut_r(i);
          end loop;
        end if;
      end if;
    --  SerCounter
      if (SerEn = '1') then
        SerCounter <= SerCounter - '1';
      else
        SerCounter <= (others => '0');
      end if;
    --  DesDataOut_r
      if (DesEn = '1') then
        DesDataOut_r(0) <= DesDataIn;
        for i in 0 to 6 loop
          DesDataOut_r(i + 1) <= DesDataOut_r(i);
        end loop;
      end if;
    --  DesCounter
      if (DesEn = '0') then
        DesCounter <= (others => '1');
      else
        DesCounter <= DesCounter - '1';
      end if;
    --  DesSTB
      if (DesCounter = "000") then
        DesSTB <= '1';
      else
        DesSTB <= '0';
      end if;
    end if;
  end process;
END ARCHITECTURE rtl;
