LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.common_utils_pkg.ALL;

ENTITY SHA1Accelerator_pipelined IS
    PORT (

        -- INPUTS 
        input_block : IN STD_LOGIC_VECTOR(511 DOWNTO 0);
        start : IN STD_LOGIC;

        clk : IN STD_LOGIC;
        nReset : IN STD_LOGIC;

        -- OUTPUTS
        done : OUT STD_LOGIC;
        hash : OUT STD_LOGIC_VECTOR(159 DOWNTO 0)

        -- DEBUG
        --debug_word_arr : OUT WORD_ARR;
        --st : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
        --curr : OUT STD_LOGIC_VECTOR(511 DOWNTO 0);
        --a_o, b_o, c_o, d_o, e_o : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
    );

END SHA1Accelerator_pipelined;

ARCHITECTURE arch_imp OF SHA1Accelerator_pipelined IS

    TYPE State IS (IDLE, setup_padding_block, wait_state, populate_words, compute_hash_20,compute_hash_40, compute_hash_60, compute_hash_80,finish_computation);
    SIGNAL a, b, c, d, e : STD_LOGIC_VECTOR(31 DOWNTO 0);

    SIGNAL curr_state : State;

    -- Make sure they are multiple of 4 
    CONSTANT num_op_cycle_word_population : INTEGER := 16; -- do not exceed 16
    CONSTANT num_op_cycle_main_loop : INTEGER := 1;
BEGIN

    --a_o <= a;
    --b_o <= b;
    --c_o <= c;
    --d_o <= d;
    --e_o <= e;

    -- DEBUG
    --WITH curr_state SELECT st <=
        --"0000" WHEN Idle,
        --"0001" WHEN populate_words,
        --"0010" WHEN compute_hash_20,
        --"0011" WHEN compute_hash_40,
        --"0100" WHEN compute_hash_60,
        --"0101" WHEN compute_hash_80,
        --"0110" WHEN wait_state,
        --"0111" WHEN setup_padding_block,
        --"1000" WHEN finish_computation;

    fsm : PROCESS (clk, nReset)
        VARIABLE words : WORD_ARR;
        VARIABLE temp : unsigned(31 DOWNTO 0);
        VARIABLE f : unsigned(31 DOWNTO 0);
        VARIABLE k : unsigned(31 DOWNTO 0);
        VARIABLE w : unsigned(31 DOWNTO 0);
        VARIABLE count : INTEGER;
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
            done <= '0';
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
                    --curr <= curr_block
                    handled_block := '0';
                    count := 0;
                    done <= '0';
                    IF start = '1' THEN
                        curr_block := input_block;
                        curr_state <= populate_words;
                    END IF;
                WHEN populate_words =>
                    a_var := unsigned(a);
                    b_var := unsigned(b);
                    c_var := unsigned(c);
                    d_var := unsigned(d);
                    e_var := unsigned(e);
                    IF count < 16/num_op_cycle_word_population THEN
                        FOR i IN 0 TO num_op_cycle_word_population - 1 LOOP
                            temp := unsigned(curr_block(511 - 32 * (i + count * num_op_cycle_word_population) DOWNTO 511 - 32 * (i + count * num_op_cycle_word_population + 1) + 1));
                            words(i + count * num_op_cycle_word_population) := temp;
                        END LOOP;
                    ELSE
                        FOR i IN 0 TO num_op_cycle_word_population - 1 LOOP
                            temp := words(i + count * num_op_cycle_word_population - 3) XOR words(i + count * num_op_cycle_word_population - 8) XOR words(i + count * num_op_cycle_word_population - 14) XOR words(i + count * num_op_cycle_word_population - 16);
                            -- words(i) = left_rotate(temp, 1)
                            words(i + count * num_op_cycle_word_population)(31 DOWNTO 1) := temp(30 DOWNTO 0);
                            words(i + count * num_op_cycle_word_population)(0) := temp(31);
                        END LOOP;
                    END IF;
                    count := count + 1;
                    IF count = 80 / num_op_cycle_word_population THEN
                        curr_state <= compute_hash_20;
                        count := 0;
                    END IF;
                    -- DEBUG
                    --debug_word_arr <= words;
                when compute_hash_20 =>
                    FOR i IN 0 TO num_op_cycle_main_loop - 1 LOOP
                        w := words(i + count * num_op_cycle_main_loop);
                        k := x"5a827999";
                        f := (b_var AND c_var) OR ((NOT b_var) AND d_var);

                        -- temp = left_rotate(a, 5)
                        temp(31 DOWNTO 5) := a_var(26 DOWNTO 0);
                        temp(4 DOWNTO 0) := a_var(31 DOWNTO 27);
                        temp := (temp + f) + (e_var + w + k);
                        e_var := d_var;
                        d_var := c_var;
                        -- c = left_rotate(b, 30);
                        c_var(31 DOWNTO 30) := b_var(1 DOWNTO 0);
                        c_var(29 DOWNTO 0) := b_var(31 DOWNTO 2);
                        b_var := a_var;
                        a_var := temp;
                    END LOOP;
                    count := count + 1;
                    if count = 20 / num_op_cycle_main_loop then 
                        curr_state <= compute_hash_40;
                        --count := 0;
                    end if;
                when compute_hash_40 =>
                    FOR i IN 0 TO num_op_cycle_main_loop - 1 LOOP
                        w := words(i + count * num_op_cycle_main_loop);
                        k := x"6ed9eba1";
                        f := b_var XOR c_var XOR d_var;

                        -- temp = left_rotate(a, 5)
                        temp(31 DOWNTO 5) := a_var(26 DOWNTO 0);
                        temp(4 DOWNTO 0) := a_var(31 DOWNTO 27);
                        temp := (temp + f) + (e_var + w + k);
                        e_var := d_var;
                        d_var := c_var;
                        -- c = left_rotate(b, 30);
                        c_var(31 DOWNTO 30) := b_var(1 DOWNTO 0);
                        c_var(29 DOWNTO 0) := b_var(31 DOWNTO 2);
                        b_var := a_var;
                        a_var := temp;
                    END LOOP;
                    count := count + 1;
                    if count = 40 / num_op_cycle_main_loop then 
                        curr_state <= compute_hash_60;
                        --count := 0;
                    end if;
                when compute_hash_60 =>
                    FOR i IN 0 TO num_op_cycle_main_loop - 1 LOOP
                        w := words(i + count * num_op_cycle_main_loop);
                        k := x"8f1bbcdc";
                        f := (b_var AND c_var) OR (b_var AND d_var) OR (c_var AND d_var);
                        -- temp = left_rotate(a, 5)
                        temp(31 DOWNTO 5) := a_var(26 DOWNTO 0);
                        temp(4 DOWNTO 0) := a_var(31 DOWNTO 27);
                        temp := (temp + f) + (e_var + w + k);
                        e_var := d_var;
                        d_var := c_var;
                        -- c = left_rotate(b, 30);
                        c_var(31 DOWNTO 30) := b_var(1 DOWNTO 0);
                        c_var(29 DOWNTO 0) := b_var(31 DOWNTO 2);
                        b_var := a_var;
                        a_var := temp;
                    END LOOP;
                    count := count + 1;
                    if count = 60 / num_op_cycle_main_loop then 
                        curr_state <= compute_hash_80;
                        --count := 0;
                    end if;
                when compute_hash_80 =>
                    FOR i IN 0 TO num_op_cycle_main_loop - 1 LOOP
                        w := words(i + count * num_op_cycle_main_loop);
                        k := x"ca62c1d6";
                        f := b_var XOR c_var XOR d_var;
                        -- temp = left_rotate(a, 5)
                        temp(31 DOWNTO 5) := a_var(26 DOWNTO 0);
                        temp(4 DOWNTO 0) := a_var(31 DOWNTO 27);
                        temp := (temp + f) + (e_var + w + k);
                        e_var := d_var;
                        d_var := c_var;
                        -- c = left_rotate(b, 30);
                        c_var(31 DOWNTO 30) := b_var(1 DOWNTO 0);
                        c_var(29 DOWNTO 0) := b_var(31 DOWNTO 2);
                        b_var := a_var;
                        a_var := temp;
                    END LOOP;
                    count := count + 1;
                    if count = 80 / num_op_cycle_main_loop then 
                        curr_state <= finish_computation;
                        count := 0;
                    end if;
                when finish_computation => 
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
                    --curr <= curr_block;
                    count := 0;
                WHEN wait_state =>
                    hash <= a & b & c & d & e;
                    done <= '1';
                    IF start = '0' THEN
                        curr_state <= Idle;
                    END IF;
                WHEN OTHERS => NULL;
            END CASE;
        END IF;
    END PROCESS fsm;
END arch_imp;