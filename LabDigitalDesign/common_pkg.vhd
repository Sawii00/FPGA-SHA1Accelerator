library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package common_utils_pkg is
    TYPE TReg IS ARRAY (natural range <>) OF STD_LOGIC_VECTOR(31 downto 0);
    TYPE ClusterControllerState IS (Idle, PrepareAndStart, WaitState);
    TYPE WORD_ARR IS ARRAY(79 DOWNTO 0) OF unsigned(31 DOWNTO 0);
    TYPE ARR_8 IS ARRAY (natural range <>) OF STD_LOGIC_VECTOR(7 downto 0);
    TYPE ARR_32 IS ARRAY (natural range <>) OF STD_LOGIC_VECTOR(31 downto 0);
    TYPE ARR_160 IS ARRAY (natural range <>) OF STD_LOGIC_VECTOR(159 downto 0);
    TYPE ARR_512 IS ARRAY (natural range <>) OF STD_LOGIC_VECTOR(511 downto 0);
end package;
    