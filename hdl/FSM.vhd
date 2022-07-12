LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.common_utils_pkg.ALL;

ENTITY FSM IS
    GENERIC (
        -- Parameters of Axi Slave Bus Interface S00_AXI
        C_S00_AXI_DATA_WIDTH : INTEGER := 32;
        C_S00_AXI_ADDR_WIDTH : INTEGER := 5;
        C_NUM_REGISTERS      : INTEGER := 5;
        -- Parameters of Axi Master Bus Interface M00_AXI
        C_M00_AXI_ADDR_WIDTH : INTEGER := 32;
        C_M00_AXI_DATA_WIDTH : INTEGER := 32;

        CLUSTER_COUNT        : INTEGER := 2
    );
    PORT (

        -- inputs
        nReset                            : IN STD_LOGIC;
        clk                               : IN STD_LOGIC;

        register_file                     : IN TReg;

        result                            : IN STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);
        finished_write                    : IN STD_LOGIC;
        finished_read                     : IN STD_LOGIC;

        -- outputs 
        read                              : OUT STD_LOGIC;
        write                             : OUT STD_LOGIC;
        address                           : OUT STD_LOGIC_VECTOR(C_M00_AXI_ADDR_WIDTH - 1 DOWNTO 0);
        data_value                        : OUT STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);

        index                             : OUT STD_LOGIC_VECTOR(C_NUM_REGISTERS - 1 DOWNTO 0);
        reg_val                           : OUT STD_LOGIC_VECTOR(C_S00_AXI_DATA_WIDTH - 1 DOWNTO 0);
        -- INPUT FROM CLUSTERS
        cluster_done                      : IN STD_LOGIC_VECTOR(CLUSTER_COUNT - 1 DOWNTO 0);
        cluster_hashes                    : IN ARR_160(CLUSTER_COUNT - 1 DOWNTO 0);
        cluster_nonces                    : IN ARR_32(CLUSTER_COUNT - 1 DOWNTO 0);
        -- OUTPUT TO CLUSTER
        cluster_blocks                    : OUT ARR_512(CLUSTER_COUNT - 1 DOWNTO 0);
        cluster_start                     : OUT STD_LOGIC_VECTOR(CLUSTER_COUNT - 1 DOWNTO 0);
        fsm_irq : out std_logic

        -- DEBUG

        --debug_state                       : OUT FSMState;
        --debug_busybitmask                 : OUT STD_LOGIC_VECTOR(CLUSTER_COUNT - 1 DOWNTO 0);
        --debug_block_offset                : OUT unsigned(2 DOWNTO 0);
        --debug_payload                     : OUT STD_LOGIC_VECTOR(191 DOWNTO 0); -- hash + nonce
        --debug_fetched_block               : OUT STD_LOGIC_VECTOR(511 DOWNTO 0);
        --debug_curr_block                  : OUT unsigned(7 DOWNTO 0);
        --debug_curr_cluster_being_serviced : OUT INTEGER
    );
END FSM;

ARCHITECTURE arch_imp OF FSM IS
    --TYPE TReg IS ARRAY (C_NUM_REGISTERS - 1 DOWNTO 0) OF STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);
    CONSTANT C_INDEX_BLOCK_ADDRESS     : INTEGER                                      := 0;
    CONSTANT C_INDEX_N_BLOCKS          : INTEGER                                      := 1;
    CONSTANT C_INDEX_DIFFICULTY        : INTEGER                                      := 2;
    CONSTANT C_INDEX_START             : INTEGER                                      := 3;
    --CONSTANT C_INDEX_STOP : INTEGER := 4;
    CONSTANT C_INDEX_DONE              : INTEGER                                      := 5;
    CONSTANT C_INDEX_RESULT_ADDR       : INTEGER                                      := 6;
    CONSTANT C_INDEX_IRQ_ENABLE : INTEGER := 7;
    CONSTANT C_INDEX_IRQ_TOGGLE : INTEGER := 8;
    CONSTANT ZERO                      : STD_LOGIC_VECTOR(CLUSTER_COUNT - 1 DOWNTO 0) := (OTHERS => '0');

    SIGNAL curr_state                  : FSMState;

    SIGNAL curr_block                  : unsigned(7 DOWNTO 0);
    SIGNAL assigned_block              : arr_8(CLUSTER_COUNT - 1 DOWNTO 0);
    SIGNAL busy_bitmask                : STD_LOGIC_VECTOR(CLUSTER_COUNT - 1 DOWNTO 0);
    SIGNAL fetched_block               : STD_LOGIC_VECTOR(511 DOWNTO 0);
    -- We let it overflow
    SIGNAL block_offset                : unsigned(2 DOWNTO 0);

    SIGNAL payload                     : STD_LOGIC_VECTOR(191 DOWNTO 0); -- hash + nonce
    SIGNAL curr_cluster_being_serviced : INTEGER;
    signal trigger_irq :          std_logic;

BEGIN

    --debug_state                       <= curr_state;
    --debug_busybitmask                 <= busy_bitmask;
    --debug_block_offset                <= block_offset;
    --debug_payload                     <= payload;
    --debug_curr_cluster_being_serviced <= curr_cluster_being_serviced;
    --debug_fetched_block               <= fetched_block;
    --debug_curr_block                  <= curr_block;

    fsm_irq <= register_file(C_INDEX_IRQ_ENABLE)(0) and trigger_irq;

    fsm : PROCESS (clk, nReset)
        VARIABLE cluster_finished  : INTEGER;
        VARIABLE cluster_available : INTEGER;
    BEGIN
        IF rising_edge(clk) THEN
            IF nReset = '0' THEN
                payload                     <= (OTHERS => '0');
                trigger_irq <= '0';
                curr_state                  <= Idle;
                curr_cluster_being_serviced <= 0;
                assigned_block              <= (OTHERS => (OTHERS => '0'));
                busy_bitmask                <= (OTHERS => '0');
                curr_block                  <= (OTHERS => '0');
                address                     <= (OTHERS => '0');
                data_value                  <= (OTHERS => '0');
                read                        <= '0';
                block_offset                <= "000";
                write                       <= '0';
                index                       <= STD_LOGIC_VECTOR(to_unsigned(C_INDEX_DONE, index'length));
                reg_val                     <= x"00000001";
                fetched_block               <= (OTHERS => '0');
                cluster_available := - 1;
                cluster_finished  := - 1;
            ELSE
                CASE(curr_state) IS
                    WHEN Idle                              =>
                    address                     <= (OTHERS => '0');
                    trigger_irq <= '0'; 
                    curr_cluster_being_serviced <= 0;
                    block_offset                <= "000";
                    payload                     <= (OTHERS => '0');
                    fetched_block               <= (OTHERS => '0');
                    data_value                  <= (OTHERS => '0');
                    read                        <= '0';
                    write                       <= '0';
                    -- This way the register file will keep the Done at 1 and the start will be modifiable by the user.
                    index                       <= STD_LOGIC_VECTOR(to_unsigned(C_INDEX_DONE, index'length));
                    reg_val                     <= x"00000001";
                    assigned_block              <= (OTHERS => (OTHERS => '0'));
                    busy_bitmask                <= (OTHERS => '0');
                    curr_block                  <= (OTHERS => '0');
                    cluster_available := - 1;
                    cluster_finished  := - 1;
                    IF register_file(C_INDEX_START)(0) = '1' THEN
                        index      <= STD_LOGIC_VECTOR(to_unsigned(C_INDEX_DONE, index'length));
                        reg_val    <= x"00000000";
                        curr_state <= state_1;
                    END IF;
                    WHEN state_1 =>
                    IF cluster_available /= - 1 THEN
                        cluster_start(cluster_available) <= '0';
                    END IF;
                    index   <= STD_LOGIC_VECTOR(to_unsigned(C_INDEX_START, index'length));
                    reg_val <= x"00000000";
                    IF curr_block < unsigned(register_file(C_INDEX_N_BLOCKS)) THEN
                        address    <= STD_LOGIC_VECTOR(unsigned(register_file(C_INDEX_BLOCK_ADDRESS)) + resize(curr_block, 16) * 64);
                        read       <= '1';
                        curr_state <= state_2;
                        --block_offset <= block_offset + 1;
                    ELSE
                        curr_state <= wait_all;
                    END IF;
                    WHEN state_2 =>
                    IF finished_read = '1' THEN
                        -- Careful timing of master read 
                        -- TODO: add to address dont recompute
                        address                                                                                            <= STD_LOGIC_VECTOR(unsigned(register_file(C_INDEX_BLOCK_ADDRESS)) + resize(curr_block, 16) * 64 + resize(block_offset, 8) * 8 + 8);
                        block_offset                                                                                       <= block_offset + 1;
                        -- Optimize if necessary
                        fetched_block(511 - to_integer(block_offset) * 64 DOWNTO 511 - 63 - to_integer(block_offset) * 64) <= result;
                        -- In theory last word of 64-bit
                        IF block_offset = "111" THEN
                            -- We assembled the whole block
                            curr_state <= state_3;
                            read       <= '0';
                        END IF;
                    END IF;
                    WHEN state_3 =>
                    cluster_available := - 1;
                    cluster_finished  := - 1;
                    FOR cluster_id IN 0 TO CLUSTER_COUNT - 1 LOOP
                        IF cluster_done(cluster_id) = '1' THEN
                            IF busy_bitmask(cluster_id) = '1' THEN
                                -- It just finished processing a block 
                                cluster_finished := cluster_id;
                            ELSE
                                cluster_available := cluster_id;
                            END IF;
                        END IF;
                    END LOOP;
                    IF cluster_available /= (-1) THEN
                        cluster_blocks(cluster_available) <= fetched_block;
                        assigned_block(cluster_available) <= STD_LOGIC_VECTOR(curr_block);
                        busy_bitmask(cluster_available)   <= '1';
                        curr_block                        <= curr_block + 1;
                        cluster_start(cluster_available)  <= '1';
                        -- NOTE: when do we de-set cluster_start??????
                        curr_state                        <= state_1;
                    ELSIF cluster_finished /= (-1) THEN
                        curr_state                  <= prepare_block_wb;
                        payload(191 DOWNTO 32)      <= cluster_hashes(cluster_finished);
                        payload(31 DOWNTO 0)        <= cluster_nonces(cluster_finished);
                        curr_cluster_being_serviced <= cluster_finished;
                        block_offset                <= "000";
                    END IF;
                    WHEN prepare_block_wb =>
                    write        <= '1';
                    data_value   <= payload(191 - to_integer(block_offset) * 64 DOWNTO 191 - 63 - to_integer(block_offset) * 64);
                    address      <= STD_LOGIC_VECTOR(unsigned(register_file(C_INDEX_RESULT_ADDR)) + resize(unsigned(assigned_block(curr_cluster_being_serviced)), 16) * 24 + resize(unsigned(block_offset), 8) * 8);
                    block_offset <= block_offset + 1;
                    curr_state   <= block_wb;
                    WHEN block_wb =>
                    IF finished_write = '1' THEN
                        IF block_offset = "011" THEN
                            -- when finished
                            busy_bitmask(curr_cluster_being_serviced)   <= '0';
                            assigned_block(curr_cluster_being_serviced) <= (OTHERS => '0');
                            curr_state                                  <= state_3;
                            block_offset                                <= "000";
                            write                                       <= '0';
                        ELSE
                            write        <= '1';
                            data_value   <= payload(191 - to_integer(block_offset) * 64 DOWNTO 191 - 63 - to_integer(block_offset) * 64);
                            address      <= STD_LOGIC_VECTOR(unsigned(register_file(C_INDEX_RESULT_ADDR)) + resize(unsigned(assigned_block(curr_cluster_being_serviced)), 16) * 24 + resize(unsigned(block_offset), 8) * 8);
                            block_offset <= block_offset + 1;
                        END IF;
                    END IF;
                    WHEN wait_all =>
                    cluster_finished := - 1;
                    FOR cluster_id IN 0 TO CLUSTER_COUNT - 1 LOOP
                        IF cluster_done(cluster_id) = '1' THEN
                            IF busy_bitmask(cluster_id) = '1' THEN
                                -- Hash computed
                                cluster_finished := cluster_id;
                            END IF;
                        END IF;
                    END LOOP;
                    IF cluster_finished /= - 1 THEN
                        curr_state                  <= prepare_block_wb2;
                        payload(191 DOWNTO 32)      <= cluster_hashes(cluster_finished);
                        payload(31 DOWNTO 0)        <= cluster_nonces(cluster_finished);
                        curr_cluster_being_serviced <= cluster_finished;
                        block_offset                <= "000";
                    ELSIF busy_bitmask = ZERO THEN
                        curr_state <= Idle;
                        trigger_irq <= '1'; 
                    END IF;
                    WHEN prepare_block_wb2 =>
                    write        <= '1';
                    data_value   <= payload(191 - to_integer(block_offset) * 64 DOWNTO 191 - 63 - to_integer(block_offset) * 64);
                    address      <= STD_LOGIC_VECTOR(unsigned(register_file(C_INDEX_RESULT_ADDR)) + resize(unsigned(assigned_block(curr_cluster_being_serviced)), 16) * 24 + resize(unsigned(block_offset), 8) * 8);
                    block_offset <= block_offset + 1;
                    curr_state   <= block_wb2;
                    WHEN block_wb2 =>
                    IF finished_write = '1' THEN
                        IF block_offset = "011" THEN
                            -- when finished
                            busy_bitmask(curr_cluster_being_serviced)   <= '0';
                            assigned_block(curr_cluster_being_serviced) <= (OTHERS => '0');
                            curr_state                                  <= wait_all;
                            block_offset                                <= "000";
                            write                                       <= '0';
                        ELSE
                            write        <= '1';
                            data_value   <= payload(191 - to_integer(block_offset) * 64 DOWNTO 191 - 63 - to_integer(block_offset) * 64);
                            address      <= STD_LOGIC_VECTOR(unsigned(register_file(C_INDEX_RESULT_ADDR)) + resize(unsigned(assigned_block(curr_cluster_being_serviced)), 16) * 24 + resize(unsigned(block_offset), 8) * 8);
                            block_offset <= block_offset + 1;
                        END IF;
                    END IF;
                    WHEN OTHERS => NULL;
                END CASE;
            END IF;
        END IF;
    END PROCESS;
END arch_imp;