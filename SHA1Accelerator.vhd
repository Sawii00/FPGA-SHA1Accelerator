LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.common_utils_pkg.ALL;
ENTITY SHA1Accelerator IS
    PORT (

        -- INPUTS 
        input_block : IN STD_LOGIC_VECTOR(511 DOWNTO 0);
        start : IN STD_LOGIC;

        clk : IN STD_LOGIC;
        nReset : IN STD_LOGIC;

        -- OUTPUTS
        done : OUT STD_LOGIC;
        hash : OUT STD_LOGIC_VECTOR(159 DOWNTO 0)

    );

END SHA1Accelerator;

ARCHITECTURE arch_imp OF SHA1Accelerator IS

    TYPE State IS (IDLE, setup_padding_block, wait_state, populate_words, compute_hash);
    SIGNAL a, b, c, d, e : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL curr_state : State;
BEGIN


    fsm : PROCESS (clk, nReset)
        VARIABLE words : WORD_ARR;
        VARIABLE temp : unsigned(31 DOWNTO 0);
        VARIABLE f : unsigned(31 DOWNTO 0);
        VARIABLE k : unsigned(31 DOWNTO 0);
        VARIABLE w : unsigned(31 DOWNTO 0);

        VARIABLE a_var : unsigned(31 DOWNTO 0);
        VARIABLE b_var : unsigned(31 DOWNTO 0);
        VARIABLE c_var : unsigned(31 DOWNTO 0);
        VARIABLE d_var : unsigned(31 DOWNTO 0);
        VARIABLE e_var : unsigned(31 DOWNTO 0);
        VARIABLE curr_block : STD_LOGIC_VECTOR(511 DOWNTO 0);

        VARIABLE handled_block : STD_LOGIC;
    BEGIN
        IF nReset = '0' THEN
            a <= x"67452301";
            b <= x"EFCDAB89";
            c <= x"98BADCFE";
            d <= x"10325476";
            e <= x"C3D2E1F0";
            curr_state <= Idle;
            handled_block := '0';
        ELSIF rising_edge(clk) THEN
            CASE curr_state IS
                WHEN Idle =>
                    a <= x"67452301";
                    b <= x"EFCDAB89";
                    c <= x"98BADCFE";
                    d <= x"10325476";
                    e <= x"C3D2E1F0";
                    curr_block := input_block;
                    curr <= curr_block;
                    handled_block := '0';
                    IF start = '1' THEN
                        curr_state <= populate_words;
                    END IF;
                WHEN populate_words =>
                    a_var := unsigned(a);
                    b_var := unsigned(b);
                    c_var := unsigned(c);
                    d_var := unsigned(d);
                    e_var := unsigned(e);
                    FOR i IN 0 TO 15 LOOP
                        temp := unsigned(curr_block(511 - 32 * i DOWNTO 511 - 32 * (i + 1) + 1));
                        words(i) := temp;
                        --words(i)(31 DOWNTO 24) := temp(7 DOWNTO 0);
                        --words(i)(23 DOWNTO 16) := temp(15 DOWNTO 8);
                        --words(i)(15 DOWNTO 8) := temp(23 DOWNTO 16);
                        --words(i)(7 DOWNTO 0) := temp(31 DOWNTO 24);
                    END LOOP;
                    FOR i IN 16 TO 79 LOOP
                        temp := words(i - 3) XOR words(i - 8) XOR words(i - 14) XOR words(i - 16);
                        -- words(i) = left_rotate(temp, 1)
                        words(i)(31 DOWNTO 1) := temp(30 DOWNTO 0);
                        words(i)(0) := temp(31);
                    END LOOP;
                    -- DEBUG
                    curr_state <= compute_hash;
                WHEN compute_hash =>
                    FOR i IN 0 TO 79 LOOP
                        k := x"00000000";
                        w := words(i);
                        IF i < 20 THEN
                            k := x"5a827999";
                            f := (b_var AND c_var) OR ((NOT b_var) AND d_var);
                        ELSIF i < 40 THEN
                            k := x"6ed9eba1";
                            f := b_var XOR c_var XOR d_var;
                        ELSIF i < 60 THEN
                            k := x"8f1bbcdc";
                            f := (b_var AND c_var) OR (b_var AND d_var) OR (c_var AND d_var);
                        ELSE
                            k := x"ca62c1d6";
                            f := b_var XOR c_var XOR d_var;
                        END IF;

                        -- temp = left_rotate(a, 5)
                        temp(31 DOWNTO 5) := a_var(26 DOWNTO 0);
                        temp(4 DOWNTO 0) := a_var(31 DOWNTO 27);
                        temp := (temp + f) + (e_var + w) + k;
                        e_var := d_var;
                        d_var := c_var;
                        -- c = left_rotate(b, 30);
                        c_var(31 DOWNTO 30) := b_var(1 DOWNTO 0);
                        c_var(29 DOWNTO 0) := b_var(31 DOWNTO 2);
                        b_var := a_var;
                        a_var := temp;
                    END LOOP;
                    a <= STD_LOGIC_VECTOR(unsigned(a) + a_var);
                    b <= STD_LOGIC_VECTOR(unsigned(b) + b_var);
                    c <= STD_LOGIC_VECTOR(unsigned(c) + c_var);
                    d <= STD_LOGIC_VECTOR(unsigned(d) + d_var);
                    e <= STD_LOGIC_VECTOR(unsigned(e) + e_var);
                    IF handled_block = '0' THEN
                        curr_state <= setup_padding_block;
                    ELSE
                        curr_state <= wait_state;
                    END IF;
                WHEN setup_padding_block =>
                    curr_block(511 DOWNTO 504) := x"80";
                    curr_block(503 DOWNTO 64) := (OTHERS => '0');
                    -- 512 in big endian within 8 bytes
                    curr_block(63 DOWNTO 0) := x"00_00_00_00_00_00_02_00";
                    handled_block := '1';
                    curr_state <= populate_words;
                    curr <= curr_block;
                WHEN wait_state =>
                    hash <= a & b & c & d & e;
                    done <= '1';
                    IF start = '0' THEN
                        curr_state <= Idle;
                        done <= '0';
                    END IF;
                WHEN OTHERS => NULL;
            END CASE;
        END IF;
    END PROCESS fsm;
END arch_imp;