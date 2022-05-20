library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package axi_package is
        TYPE TReg IS ARRAY (natural range <>) OF STD_LOGIC_VECTOR(31 downto 0);
end package;
    