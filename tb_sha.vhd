LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
use work.common_utils_pkg.all;

ENTITY tb_sha IS
END tb_sha;

ARCHITECTURE arch_imp OF tb_sha IS
    signal clk: std_logic;
    signal nReset : std_logic;
    signal input_block : std_logic_vector(511 downto 0);
    signal hash : std_logic_vector(159 downto 0);
    signal start : std_logic;
    signal done : std_logic;
	 signal st : std_logic_vector(2 downto 0);
     signal debug_word_arr : WORD_ARR;

    constant CLK_PERIOD : time:= 20 ns;

BEGIN

    hasher: entity work.SHA1Accelerator
        port map(
				input_block => input_block,
            clk => clk,
            nReset => nReset,
            hash => hash,
            start => start,
            done => done,
                debug_word_arr => debug_word_arr,
				st => st
        );

    ckl_generation: process
    begin
        CLK <= '1';
        wait for CLK_PERIOD / 2;
        CLK <= '0';
        wait for CLK_PERIOD / 2;
    end process;

   tb: process
   begin
        wait for 5 * CLK_PERIOD/4;
        nReset <= '0';
        wait for 5 * CLK_PERIOD;
        nReset <= '1';

        input_block <= (others => '1');
        start <= '1';
        wait until done = '1';
		  wait for CLK_PERIOD/4;
        start <= '0';
	wait;

   end process tb;



END arch_imp;