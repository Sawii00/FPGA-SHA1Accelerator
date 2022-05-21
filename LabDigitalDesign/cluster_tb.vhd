LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.common_utils_pkg.ALL;

ENTITY tb_cluster IS
END tb_cluster;

ARCHITECTURE arch_imp OF tb_cluster IS
    SIGNAL clk : STD_LOGIC;
    SIGNAL nReset : STD_LOGIC;

    SIGNAL input_block : STD_LOGIC_VECTOR(511 DOWNTO 0);
    SIGNAL start : STD_LOGIC;
    SIGNAL stop : STD_LOGIC;
    SIGNAL difficulty : STD_LOGIC_VECTOR(31 DOWNTO 0); -- Used as a mask (111000...000 means start with 3 zeros)

    SIGNAL done : STD_LOGIC;
    SIGNAL hash : STD_LOGIC_VECTOR(159 DOWNTO 0);
    SIGNAL nonce : STD_LOGIC_VECTOR(31 DOWNTO 0);

    CONSTANT CLK_PERIOD : TIME := 20 ns;

    SIGNAL debug_state : ClusterControllerState;
    SIGNAL debug_hash_start : STD_LOGIC;
    SIGNAL debug_hash_nonces : arr_32(3 DOWNTO 0);
    SIGNAL debug_hash_done : STD_LOGIC;
    SIGNAL debug_reset_system : STD_LOGIC;
    SIGNAL debug_hash_done_all : STD_LOGIC_VECTOR(4 - 1 DOWNTO 0);

BEGIN

    hasher : ENTITY work.Cluster
        PORT MAP(
            clk => clk,
            nReset => nReset,
            input_block => input_block,
            start => start,
            stop => stop,
            difficulty => difficulty,
            done => done,
            debug_state => debug_state,
            debug_hash_nonces => debug_hash_nonces,
            debug_hash_start => debug_hash_start,
            debug_hash_done => debug_hash_done,
            debug_hash_done_all => debug_hash_done_all,
            debug_reset_system => debug_reset_system,
            hash => hash,
            nonce => nonce
        );

    ckl_generation : PROCESS
    BEGIN
        CLK <= '1';
        WAIT FOR CLK_PERIOD / 2;
        CLK <= '0';
        WAIT FOR CLK_PERIOD / 2;
    END PROCESS;

    tb : PROCESS
    BEGIN
        WAIT FOR 5 * CLK_PERIOD/4;
        nReset <= '0';
        WAIT FOR 5 * CLK_PERIOD;
        nReset <= '1';
        stop <= '0';

        input_block <= (OTHERS => '1');
        difficulty <= x"f0000000";
        start <= '1';
        WAIT FOR 2 * CLK_PERIOD;
        start <= '0';
        WAIT FOR 10 * CLK_PERIOD;
        stop <= '1';
        WAIT FOR 2 * CLK_PERIOD;
        stop <= '0';

        start <= '1';
        WAIT FOR 2 * CLK_PERIOD;
        start <= '0';

        WAIT UNTIL done = '1';

        WAIT;
    END PROCESS tb;

END ARCHITECTURE arch_imp;