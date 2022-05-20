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
        difficulty : IN STD_LOGIC_VECTOR(31 DOWNTO 0); -- Used as a mask (111000...000 means start with 3 zeros)

        clk : IN STD_LOGIC;
        nReset : IN STD_LOGIC;

        -- OUTPUTS
        done : OUT STD_LOGIC;
        hash : OUT STD_LOGIC_VECTOR(159 DOWNTO 0);
        nonce : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)

    );

END Cluster;

ARCHITECTURE arch_imp OF Cluster IS
    SIGNAL hash_done : STD_LOGIC_VECTOR(N_HASHERS - 1 downto 0);
    signal hash_done_or : std_logic;
    SIGNAL hash_results : ARR_160(N_HASHERS - 1 DOWNTO 0);

    SIGNAL hash_start : STD_LOGIC;
    SIGNAL hash_nonces : arr_32(N_HASHERS - 1 DOWNTO 0);

BEGIN

    controller : ENTITY work.ClusterController
        GENERIC MAP(N_HASHERS => N_HASHERS)
        PORT MAP(
            start => start,
            difficulty => difficulty,
            clk => clk,
            nReset => nReset,
            hash_done => hash_done_or,
            hash_results => hash_results,
            done => done,
            hash => hash,
            nonce => nonce,
            hash_start => hash_start,
            hash_nonces => hash_nonces
        );

    hash_generation :
    FOR i IN 0 TO N_HASHERS - 1 GENERATE
        hasher : ENTITY work.SHA1Accelerator_pipelined(rtl)
            PORT MAP(
                input_block (511 downto 32) => input_block (511 downto 32),
                input_block(31 downto 0) => hash_nonces(i),
                start => hash_start,
                clk => clk,
                nReset => nReset,
                done => hash_done(i),
                hash => hash_results(i)
            );
    END GENERATE hash_generation;

    done_or_set : 
    for i in 0 to N_HASHERS - 1 GENERATE
        hash_done_or <= hash_done_or or hash_done(i);
    end GENERATE done_or_set;

END ARCHITECTURE arch_imp;