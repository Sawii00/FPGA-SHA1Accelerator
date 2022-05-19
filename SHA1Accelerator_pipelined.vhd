LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
use work.common_utils_pkg.all;


ENTITY SHA1Accelerator IS
    PORT (

        -- INPUTS 
        input_block : IN STD_LOGIC_VECTOR(511 DOWNTO 0);
        start : IN STD_LOGIC;

        clk : IN STD_LOGIC;
        nReset : IN STD_LOGIC;

        -- OUTPUTS
        done : OUT STD_LOGIC;
        hash : OUT STD_LOGIC_VECTOR(159 DOWNTO 0);

        -- DEBUG
        debug_word_arr : out WORD_ARR;
        st : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
		  curr : out std_logic_vector(511 downto 0);
		  a_o, b_o, c_o, d_o, e_o : out std_logic_vector(31 downto 0)
    );

END SHA1Accelerator;

ARCHITECTURE arch_imp OF SHA1Accelerator IS

    TYPE State IS (IDLE, setup_padding_block, wait_state, populate_words, compute_hash);
    SIGNAL a, b, c, d, e : STD_LOGIC_VECTOR(31 DOWNTO 0);

    SIGNAL curr_state : State;
	 
	 constant num_op_cycle : integer := 4;
BEGIN

	a_o <= a;
	b_o <= b;
	c_o <= c;
	d_o <= d;
	e_o <= e;

    -- DEBUG
    WITH curr_state SELECT st <=
        "000" WHEN Idle,
        "001" WHEN populate_words,
        "010" WHEN compute_hash,
        "011" WHEN wait_state,
        "100" when setup_padding_block;

    fsm : PROCESS (clk, nReset)
        VARIABLE words : WORD_ARR;
        VARIABLE temp : unsigned(31 DOWNTO 0);
        VARIABLE f : unsigned(31 DOWNTO 0);
        VARIABLE k : unsigned(31 DOWNTO 0);
        VARIABLE w : unsigned(31 DOWNTO 0);
		  VARIABLE count : integer;


        VARIABLE a_var : unsigned(31 DOWNTO 0);
        VARIABLE b_var : unsigned(31 DOWNTO 0);
        VARIABLE c_var : unsigned(31 DOWNTO 0);
        VARIABLE d_var : unsigned(31 DOWNTO 0);
        VARIABLE e_var : unsigned(31 DOWNTO 0);
        variable curr_block : STD_LOGIC_VECTOR(511 DOWNTO 0);

        variable handled_block : std_logic;
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
						  count := 0;
						  
                    IF start = '1' THEN
                        curr_state <= populate_words;
                    END IF;
                WHEN populate_words =>
                    a_var := unsigned(a);
                    b_var := unsigned(b);
                    c_var := unsigned(c);
                    d_var := unsigned(d);
                    e_var := unsigned(e);
						  
						  
						  if count < 16/num_op_cycle then
									for i in 0 to num_op_cycle - 1 loop
										temp:= unsigned(curr_block(511 - 32*(i + count*num_op_cycle) downto 511 -32*(i + count*num_op_cycle + 1) + 1));
										words(i + count*num_op_cycle) := temp;
								END LOOP;
						  else
								for i in 0 to num_op_cycle - 1 loop
									temp := words(i + count*num_op_cycle - 3) XOR words(i + count*num_op_cycle - 8) XOR words(i + count*num_op_cycle - 14) XOR words(i + count*num_op_cycle - 16);
									-- words(i) = left_rotate(temp, 1)
									words(i + count*num_op_cycle)(31 DOWNTO 1) := temp(30 DOWNTO 0);
									words(i + count*num_op_cycle)(0) := temp(31);
								END LOOP;
						  end if;
						  count := count + 1;
						  if count >= 80 / num_op_cycle then
								curr_state <= compute_hash;
								count := 0;
						  end if;
                    -- DEBUG
                    debug_word_arr<= words;
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
                    if handled_block = '0' THEN
                        curr_state <= setup_padding_block;
                    ELSE
                        curr_state <= wait_state;
                    end if;
                when setup_padding_block =>
                    curr_block(511 downto 504) := x"80";
                    curr_block(503 downto 64) := (others => '0');
                    -- 512 in big endian within 8 bytes
                    curr_block(63 downto 0) := x"00_00_00_00_00_00_02_00";
                    handled_block := '1';
                    curr_state <= populate_words;
						  curr <= curr_block;
						  count := 0;
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