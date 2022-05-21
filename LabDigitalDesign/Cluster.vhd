LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.common_utils_pkg.ALL;

ENTITY Cluster IS
    GENERIC (
        N_HASHERS : INTEGER := 4
    );

    PORT (

        input_block : IN STD_LOGIC_VECTOR(511 DOWNTO 0);
        start : IN STD_LOGIC;
        stop : IN STD_LOGIC;
        difficulty : IN STD_LOGIC_VECTOR(31 DOWNTO 0); -- Used as a mask (111000...000 means start with 3 zeros)

        clk : IN STD_LOGIC;
        nReset : IN STD_LOGIC;

        -- OUTPUTS
        done : OUT STD_LOGIC;
        hash : OUT STD_LOGIC_VECTOR(159 DOWNTO 0);
        nonce : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);

        -- DEBUG
        debug_state : OUT ClusterControllerState;
        debug_hash_start : OUT STD_LOGIC;
        debug_hash_nonces : OUT arr_32(N_HASHERS - 1 DOWNTO 0);
        debug_hash_done : OUT STD_LOGIC;
        debug_hash_done_all : OUT STD_LOGIC_VECTOR(N_HASHERS - 1 DOWNTO 0);
        debug_reset_system : OUT STD_LOGIC

    );

END Cluster;

ARCHITECTURE arch_imp OF Cluster IS
    SIGNAL hash_done : STD_LOGIC_VECTOR(N_HASHERS - 1 DOWNTO 0);
    SIGNAL hash_done_or : STD_LOGIC := '0';

    SIGNAL hash_results : ARR_160(N_HASHERS - 1 DOWNTO 0);

    SIGNAL hash_start : STD_LOGIC;
    SIGNAL hash_nonces : arr_32(N_HASHERS - 1 DOWNTO 0);

    SIGNAL reset_system : STD_LOGIC;

    -- DEBUG
    SIGNAL debug_state_fsm : ClusterControllerState;

BEGIN
    debug_hash_nonces <= hash_nonces;
    debug_state <= debug_state_fsm;
    debug_hash_start <= hash_start;
    debug_hash_done <= hash_done_or;
    debug_hash_done_all <= hash_done;
    debug_reset_system <= reset_system;

    reset_system <= nReset AND NOT stop;

    controller : ENTITY work.ClusterController
        GENERIC MAP(N_HASHERS => N_HASHERS)
        PORT MAP(
            start => start,
            difficulty => difficulty,
            clk => clk,
            nReset => reset_system,
            hash_done => hash_done_or,
            hash_results => hash_results,
            done => done,
            hash => hash,
            nonce => nonce,
            hash_start => hash_start,
            hash_nonces => hash_nonces,
            debug_state => debug_state_fsm
        );

    hash_generation :
    FOR i IN 0 TO N_HASHERS - 1 GENERATE
        hasher : ENTITY work.SHA1Accelerator_pipelined
            PORT MAP(
                input_block (511 DOWNTO 32) => input_block (511 DOWNTO 32),
                input_block(31 DOWNTO 0) => hash_nonces(i),
                start => hash_start,
                clk => clk,
                nReset => reset_system,
                done => hash_done(i),
                hash => hash_results(i)
            );
    END GENERATE hash_generation;

    --done_or_set :
    --FOR i IN 0 TO N_HASHERS - 1 GENERATE
    --hash_done_or <= hash_done_or OR hash_done(i);
    --END GENERATE done_or_set;
    -- THEY ALL FINISH AT THE SAME TIME ANYWAY
    hash_done_or <= hash_done(0);

END ARCHITECTURE arch_imp;