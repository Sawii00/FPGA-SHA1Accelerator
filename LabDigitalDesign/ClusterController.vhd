LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.common_utils_pkg.ALL;

ENTITY ClusterController IS

    GENERIC (
        N_HASHERS : INTEGER := 4
    );
    PORT (
        -- INPUTS FROM OUTSIDE
        --input_block : IN STD_LOGIC_VECTOR(511 DOWNTO 0);
        start : IN STD_LOGIC;
        difficulty : IN STD_LOGIC_VECTOR(31 DOWNTO 0); -- Used as a mask (111000...000 means start with 3 zeros)

        clk : IN STD_LOGIC;
        nReset : IN STD_LOGIC;

        -- INPUT FROM HASHERS
        hash_done : IN STD_LOGIC; -- OR of all done signals
        hash_results : IN ARR_160(N_HASHERS - 1 DOWNTO 0);

        -- OUTPUTS TO MAIN CONTROLLER 
        done : OUT STD_LOGIC;
        hash : OUT STD_LOGIC_VECTOR(159 DOWNTO 0);
        nonce : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);

        -- OUTPUT TO HASHERS
        hash_start : OUT STD_LOGIC;
        -- Cluster Top level must connect the nonce to last 32 bits of the block to the hashers
        hash_nonces : INOUT ARR_32(N_HASHERS - 1 DOWNTO 0);


        -- DEBUG
        debug_state :out  ClusterControllerState
    );

END ClusterController;

ARCHITECTURE arch_imp OF ClusterController IS

    SIGNAL curr_state : ClusterControllerState;

BEGIN

    debug_state <= curr_state;

    fsm : PROCESS (clk, nReset)
        VARIABLE curr_nonce : unsigned(31 DOWNTO 0);
        VARIABLE correct_nonce : STD_LOGIC_VECTOR(31 DOWNTO 0);
        VARIABLE correct_hash_id : INTEGER RANGE 0 TO N_HASHERS; -- N_HASHERS used as default value
    BEGIN
        IF nReset = '0' THEN
            curr_state <= Idle;
            done <= '0';
            nonce <= (OTHERS => '0');
            hash <= (OTHERS => '0');
            hash_start <= '0';
            correct_nonce := (OTHERS => '0');
            correct_hash_id := N_HASHERS;
            hash_nonces <= (OTHERS => (OTHERS => '0'));
            curr_nonce := (OTHERS => '0');
        ELSIF rising_edge(clk) THEN
            CASE curr_state IS
                WHEN Idle =>
                    done <= '0';
                    nonce <= (OTHERS => '0');
                    hash <= (OTHERS => '0');
                    hash_start <= '0';
                    hash_nonces <= (OTHERS => (OTHERS => '0'));
                    correct_nonce := (OTHERS => '0');
                    correct_hash_id := N_HASHERS;
                    curr_nonce := (OTHERS => '0');
                    IF start = '1' THEN
                        curr_state <= PrepareAndStart;
                        -- Save block? Probably not
                    END IF;
                WHEN PrepareAndStart =>
                    FOR i IN 0 TO N_HASHERS - 1 LOOP
                        hash_nonces(i) <= STD_LOGIC_VECTOR(curr_nonce);
                        curr_nonce := curr_nonce + 1;
                    END LOOP;
                    hash_start <= '1';
                    curr_state <= WaitState;
                WHEN WaitState =>
                    hash_start <= '0';
                    IF hash_done = '1' THEN
                        FOR i IN 0 TO N_HASHERS - 1 LOOP
                            IF (hash_results(i)(159 DOWNTO 159 - 31) AND difficulty) = x"00000000" THEN
                                correct_nonce := hash_nonces(i);
                                correct_hash_id := i;
                            END IF;
                        END LOOP;
                        IF correct_hash_id /= N_HASHERS THEN
                            done <= '1';
                            nonce <= correct_nonce;
                            hash <= hash_results(correct_hash_id);
                            curr_state <= Idle;
                        ELSE
                            curr_state <= PrepareAndStart;
                        END IF;
                    END IF;
                WHEN OTHERS => NULL;
            END CASE;
        END IF;
    END PROCESS fsm;

END ARCHITECTURE arch_imp;