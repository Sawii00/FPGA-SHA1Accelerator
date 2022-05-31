LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.common_utils_pkg.ALL;

ENTITY fifo_tb IS
END fifo_tb;

ARCHITECTURE arch_imp OF fifo_tb IS

    CONSTANT C_M00_AXI_ADDR_WIDTH            : INTEGER := 32;
    CONSTANT C_M00_AXI_DATA_WIDTH            : INTEGER := 64;
    CONSTANT C_S00_AXI_DATA_WIDTH            : INTEGER := 32;
    CONSTANT CLUSTER_COUNT                   : INTEGER := 2;
    CONSTANT C_NUM_REGISTERS                 : INTEGER := 7;
    CONSTANT C_INDEX_BLOCK_ADDRESS           : INTEGER := 0;
    CONSTANT C_INDEX_N_BLOCKS                : INTEGER := 1;
    CONSTANT C_INDEX_DIFFICULTY              : INTEGER := 2;
    CONSTANT C_INDEX_START                   : INTEGER := 3;
    CONSTANT C_INDEX_STOP                    : INTEGER := 4;
    CONSTANT C_INDEX_DONE                    : INTEGER := 5;
    CONSTANT C_INDEX_RESULT_ADDR             : INTEGER := 6;
    CONSTANT C_INDEX_IRQ_ENABLE              : INTEGER := 7;
    CONSTANT C_INDEX_IRQ_TOGGLE              : INTEGER := 8;

    SIGNAL clk                               : STD_LOGIC;
    SIGNAL nReset                            : STD_LOGIC;

    SIGNAL register_file                     : TReg(6 DOWNTO 0);

    SIGNAL result                            : STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL finished_write                    : STD_LOGIC;
    SIGNAL finished_read                     : STD_LOGIC;

    -- outputs 
    SIGNAL read                              : STD_LOGIC;
    SIGNAL write                             : STD_LOGIC;
    SIGNAL address                           : STD_LOGIC_VECTOR(C_M00_AXI_ADDR_WIDTH - 1 DOWNTO 0);
    SIGNAL data_value                        : STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);

    SIGNAL index                             : STD_LOGIC_VECTOR(C_NUM_REGISTERS - 1 DOWNTO 0);
    SIGNAL reg_val                           : STD_LOGIC_VECTOR(C_S00_AXI_DATA_WIDTH - 1 DOWNTO 0);
    -- INPUT FROM CLUSTERS
    SIGNAL cluster_done                      : STD_LOGIC_VECTOR(CLUSTER_COUNT - 1 DOWNTO 0);
    SIGNAL cluster_hashes                    : ARR_160(CLUSTER_COUNT - 1 DOWNTO 0);
    SIGNAL cluster_nonces                    : ARR_32(CLUSTER_COUNT - 1 DOWNTO 0);
    -- OUTPUT TO CLUSTER
    SIGNAL cluster_blocks                    : ARR_512(CLUSTER_COUNT - 1 DOWNTO 0);
    SIGNAL cluster_start                     : STD_LOGIC_VECTOR(CLUSTER_COUNT - 1 DOWNTO 0);

    CONSTANT CLK_PERIOD                      : TIME := 20 ns;

    SIGNAL debug_state                       : FSMState;
    SIGNAL debug_busybitmask                 : STD_LOGIC_VECTOR(CLUSTER_COUNT - 1 DOWNTO 0);
    SIGNAL debug_block_offset                : unsigned(2 DOWNTO 0);
    SIGNAL debug_curr_block                  : unsigned(7 DOWNTO 0);
    SIGNAL debug_payload                     : STD_LOGIC_VECTOR(191 DOWNTO 0); -- hash + nonce
    SIGNAL debug_curr_cluster_being_serviced : INTEGER;
    SIGNAL debug_fetched_block               : STD_LOGIC_VECTOR(511 DOWNTO 0);

    SIGNAL out_state                         : fifo_controller_state_axi;
    SIGNAL rden_out                          : STD_LOGIC;
    SIGNAL wren_out                          : STD_LOGIC;
    SIGNAL curr_block_out                    : unsigned(7 DOWNTO 0);
    SIGNAL block_offset_out                  : unsigned(2 DOWNTO 0);
    SIGNAL DI_out                            : STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL DO_out                            : STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL rst_out                           : STD_LOGIC;
    SIGNAL is_resetting_out                  : STD_LOGIC;

    SIGNAL read_axi                          : STD_LOGIC;
    SIGNAL finished_read_axi                 : STD_LOGIC;
    SIGNAL address_axi                       : STD_LOGIC_VECTOR(C_M00_AXI_ADDR_WIDTH - 1 DOWNTO 0);
    SIGNAL result_axi                        : STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);
BEGIN

    fifo_contr_debug : ENTITY work.FIFOController
        GENERIC MAP(
            C_M00_AXI_DATA_WIDTH => C_M00_AXI_DATA_WIDTH,
            C_M00_AXI_ADDR_WIDTH => C_M00_AXI_ADDR_WIDTH
        )
        PORT MAP(
            clk               => clk,
            nReset            => nReset,

            n_blocks          => unsigned(register_file(C_INDEX_N_BLOCKS)(7 DOWNTO 0)),
            start             => register_file(C_INDEX_START)(0),
            read              => read,
            finished_read     => finished_read,

            -- Towards Axi Master
            read_axi          => read_axi,
            finished_read_axi => finished_read_axi,
            address_axi       => address_axi,
            result_axi        => result_axi,

            result            => result,
            block_address     => register_file(C_INDEX_BLOCK_ADDRESS),
            out_state         => out_state,
            rden_out          => rden_out,
            wren_out          => wren_out,
            curr_block_out    => curr_block_out,
            block_offset_out  => block_offset_out,
            DI_out            => DI_out,
            DO_out            => DO_out,
            rst_out => rst_out,
            is_resetting_out => is_resetting_out
        );
    hasher : ENTITY work.FSM
        GENERIC MAP(
            C_M00_AXI_ADDR_WIDTH => C_M00_AXI_ADDR_WIDTH,
            C_M00_AXI_data_WIDTH => C_M00_AXI_data_WIDTH,
            C_NUM_REGISTERS      => C_NUM_REGISTERS
        )
        PORT MAP(
            clk                               => clk,
            nReset                            => nReset,
            register_file                     => register_file,
            result                            => result,
            finished_write                    => finished_write,
            finished_read                     => finished_read,
            read                              => read,
            write                             => write,
            address                           => address,
            data_value                        => data_value,
            index                             => index,
            reg_val                           => reg_val,
            cluster_done                      => cluster_done,
            cluster_hashes                    => cluster_hashes,
            cluster_nonces                    => cluster_nonces,
            cluster_blocks                    => cluster_blocks,
            cluster_start                     => cluster_start,
            debug_state                       => debug_state,
            debug_busybitmask                 => debug_busybitmask,
            debug_block_offset                => debug_block_offset,
            debug_payload                     => debug_payload,
            debug_curr_cluster_being_serviced => debug_curr_cluster_being_serviced,
            debug_curr_block                  => debug_curr_block,
            debug_fetched_block               => debug_fetched_block
        );
    clusters : FOR i IN 0 TO CLUSTER_COUNT - 1 GENERATE
        hasher : ENTITY work.Cluster
            PORT MAP(
                input_block => cluster_blocks(i),
                start       => cluster_start(i),
                stop        => '0',
                difficulty  => register_file(2),

                clk         => clk,
                nReset      => nReset,

                -- OUTPUTS
                done        => cluster_done(i),
                hash        => cluster_hashes(i),
                nonce       => cluster_nonces(i)
            );
    END GENERATE clusters;

    ckl_generation : PROCESS
    BEGIN
        CLK <= '1';
        WAIT FOR CLK_PERIOD / 2;
        CLK <= '0';
        WAIT FOR CLK_PERIOD / 2;
    END PROCESS;

    tb : PROCESS
    BEGIN
        -- Reset
        WAIT FOR 5 * CLK_PERIOD/4;
        nReset <= '0';
        WAIT FOR 5 * CLK_PERIOD;
        nReset           <= '1';

        -- Register File Setup
        register_file(0) <= x"00000000"; -- block address
        register_file(1) <= x"00000004"; -- n_blocks
        register_file(2) <= x"ff000000"; -- difficulty mask
        register_file(6) <= x"ffff0000"; -- hash address

        WAIT FOR 2 * CLK_PERIOD;
        register_file(3) <= x"00000001"; -- start FSM

        WAIT FOR 8 * CLK_PERIOD;
        register_file(3) <= x"00000000"; -- start FSM

        -- Provide first block
        WAIT FOR 2 * CLK_PERIOD;
        result_axi        <= x"2222222222222222";
        finished_read_axi <= '1';
        WAIT FOR CLK_PERIOD;
        finished_read_axi <= '0';
        WAIT FOR 2 * CLK_PERIOD;
        result_axi        <= x"3434343434343434";
        finished_read_axi <= '1';
        FOR i IN 2 TO 7 LOOP
            WAIT FOR CLK_PERIOD;
            result_axi        <= x"0191234578625321";
            finished_read_axi <= '1';
        END LOOP;
        WAIT FOR CLK_PERIOD;
        finished_read_axi <= '0';

        -- Provide Block 2
        WAIT UNTIL read_axi = '1';
        WAIT FOR 2 * CLK_PERIOD;
        result_axi        <= x"aabbccddeeff0011";
        finished_read_axi <= '1';
        WAIT FOR CLK_PERIOD;
        finished_read_axi <= '0';
        WAIT FOR 2 * CLK_PERIOD;
        result_axi        <= x"1010010100001111";
        finished_read_axi <= '1';
        FOR i IN 2 TO 7 LOOP
            WAIT FOR CLK_PERIOD;
            result_axi        <= x"1122334455667788";
            finished_read_axi <= '1';
        END LOOP;
        WAIT FOR CLK_PERIOD;
        finished_read_axi <= '0';

        -- Provide Block 3
        WAIT UNTIL read_axi = '1';
        WAIT FOR 2 * CLK_PERIOD;
        result_axi        <= x"ffffffffffffffff";
        finished_read_axi <= '1';
        WAIT FOR CLK_PERIOD;
        finished_read_axi <= '0';
        WAIT FOR 2 * CLK_PERIOD;
        result_axi        <= x"0000000000000000";
        finished_read_axi <= '1';
        FOR i IN 2 TO 7 LOOP
            WAIT FOR CLK_PERIOD;
            result_axi        <= x"f0f0f0f00f0f0f0f";
            finished_read_axi <= '1';
        END LOOP;
        WAIT FOR CLK_PERIOD;
        finished_read_axi <= '0';

        WAIT UNTIL write = '1';
        FOR i IN 0 TO 2 LOOP
            WAIT FOR CLK_PERIOD;
            finished_write <= '1';
        END LOOP;
        WAIT FOR CLK_PERIOD;
        finished_write <= '0';
        WAIT FOR CLK_PERIOD;

        -- Provide block 4
        WAIT UNTIL read_axi = '1';
        WAIT FOR 2 * CLK_PERIOD;
        result_axi        <= x"ffffffffffffffff";
        finished_read_axi <= '1';
        WAIT FOR CLK_PERIOD;
        finished_read_axi <= '0';
        WAIT FOR 2 * CLK_PERIOD;
        result_axi        <= x"0000000000000000";
        finished_read_axi <= '1';
        FOR i IN 2 TO 7 LOOP
            WAIT FOR CLK_PERIOD;
            result_axi        <= x"f0f0f0f00f0f0f0f";
            finished_read_axi <= '1';
        END LOOP;
        WAIT FOR CLK_PERIOD;
        finished_read_axi <= '0';

        WAIT UNTIL write = '1';
        FOR i IN 0 TO 2 LOOP
            WAIT FOR CLK_PERIOD;
            finished_write <= '1';
        END LOOP;
        WAIT FOR CLK_PERIOD;
        finished_write <= '0';
        WAIT FOR CLK_PERIOD;

        WAIT UNTIL write = '1';
        FOR i IN 0 TO 2 LOOP
            WAIT FOR CLK_PERIOD;
            finished_write <= '1';
        END LOOP;
        WAIT FOR CLK_PERIOD;
        finished_write <= '0';
        WAIT FOR CLK_PERIOD;

        WAIT UNTIL write = '1';
        FOR i IN 0 TO 2 LOOP
            WAIT FOR CLK_PERIOD;
            finished_write <= '1';
        END LOOP;
        WAIT FOR CLK_PERIOD;
        finished_write <= '0';
        WAIT FOR CLK_PERIOD;

        WAIT UNTIL write = '1';
        FOR i IN 0 TO 2 LOOP
            WAIT FOR CLK_PERIOD;
            finished_write <= '1';
        END LOOP;
        WAIT FOR CLK_PERIOD;
        finished_write <= '0';
        WAIT FOR CLK_PERIOD;
        WAIT;
    END PROCESS tb;

END ARCHITECTURE arch_imp;