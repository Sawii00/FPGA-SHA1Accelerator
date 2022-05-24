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
        nReset         : IN STD_LOGIC;
        clk            : IN STD_LOGIC;

        register_file  : IN TReg;

        result         : IN STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);
        finished_write : IN STD_LOGIC;
        finished_read  : IN STD_LOGIC;

        -- outputs 
        read           : OUT STD_LOGIC;
        write          : OUT STD_LOGIC;
        address        : OUT STD_LOGIC_VECTOR(C_M00_AXI_ADDR_WIDTH - 1 DOWNTO 0);
        data_value     : OUT STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);

        index          : OUT STD_LOGIC_VECTOR(C_NUM_REGISTERS - 1 DOWNTO 0);
        reg_val        : OUT STD_LOGIC_VECTOR(C_S00_AXI_DATA_WIDTH - 1 DOWNTO 0);
        -- INPUT FROM CLUSTERS
        cluster_done   : IN STD_LOGIC_VECTOR(CLUSTER_COUNT - 1 DOWNTO 0);
        cluster_hashes : IN ARR_160(CLUSTER_COUNT - 1 DOWNTO 0);
        cluster_nonces : IN ARR_32(CLUSTER_COUNT - 1 DOWNTO 0);
        -- OUTPUT TO CLUSTER
        cluster_blocks : OUT ARR_512(CLUSTER_COUNT - 1 DOWNTO 0);
        cluster_start  : OUT STD_LOGIC_VECTOR(CLUSTER_COUNT - 1 DOWNTO 0)
    );
END FSM;

ARCHITECTURE arch_imp OF FSM IS
    --TYPE TReg IS ARRAY (C_NUM_REGISTERS - 1 DOWNTO 0) OF STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);
    CONSTANT C_INDEX_BLOCK_ADDRESS : INTEGER                                      := 0;
    CONSTANT C_INDEX_N_BLOCKS      : INTEGER                                      := 1;
    CONSTANT C_INDEX_DIFFICULTY    : INTEGER                                      := 2;
    CONSTANT C_INDEX_START         : INTEGER                                      := 3;
    --CONSTANT C_INDEX_STOP : INTEGER := 4;
    CONSTANT C_INDEX_DONE          : INTEGER                                      := 5;
    CONSTANT C_INDEX_RESULT_ADDR   : INTEGER                                      := 6;

    CONSTANT ZERO                  : STD_LOGIC_VECTOR(CLUSTER_COUNT - 1 DOWNTO 0) := (OTHERS => '0');

    TYPE FSMState IS (IDLE, state_1, state_2, state_3, wait_all, block_wb, block_wb2, prepare_block_wb, prepare_block_wb2);
    SIGNAL curr_state                  : FSMState;

    SIGNAL curr_block                  : unsigned(7 DOWNTO 0);
    SIGNAL assigned_block              : arr_8(CLUSTER_COUNT - 1 DOWNTO 0);
    SIGNAL busy_bitmask                : STD_LOGIC_VECTOR(CLUSTER_COUNT - 1 DOWNTO 0);
    SIGNAL fetched_block               : STD_LOGIC_VECTOR(511 DOWNTO 0);
    -- We let it overflow
    SIGNAL block_offset                : unsigned(2 DOWNTO 0);

    SIGNAL payload                     : STD_LOGIC_VECTOR(191 DOWNTO 0); -- hash + nonce
    SIGNAL curr_cluster_being_serviced : INTEGER;

BEGIN
    fsm : PROCESS (clk, nReset)
        VARIABLE cluster_finished  : INTEGER;
        VARIABLE cluster_available : INTEGER;
    BEGIN
        IF rising_edge(clk) THEN
            IF nReset = '0' THEN
                payload                     <= (OTHERS => '0');
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
                        address    <= STD_LOGIC_VECTOR(unsigned(register_file(C_INDEX_BLOCK_ADDRESS)) + shift_left(curr_block, 6));
                        read       <= '1';
                        curr_state <= state_2;
                    ELSE
                        curr_state <= wait_all;
                    END IF;
                    WHEN state_2 =>
                    IF finished_read = '1' THEN
                        -- Careful timing of master read 
                        -- TODO: add to address dont recompute
                        address                                                                                                                <= STD_LOGIC_VECTOR(unsigned(register_file(C_INDEX_BLOCK_ADDRESS)) + shift_left(curr_block, 6) + shift_left(block_offset, 3));
                        block_offset I                                                                                                         <= block_offset + 1;
                        -- Optimize if necessary
                        fetched_block(511 - to_integer(shift_left(block_offset, 6)) DOWNTO 511 - 63 - to_integer(shift_left(block_offset, 6))) <= result;
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
                        -- This does not work since we execute the following snippet for every cluster and thus will overwrite the previous values.
                        -- Maybe it's ok if we are fine with always picking the latest cluster available (in terms of id)
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
                    data_value   <= payload(191 - to_integer(shift_left(block_offset, 6)) DOWNTO 191 - 63 - to_integer(shift_left(block_offset, 6)));
                    address      <= STD_LOGIC_VECTOR(unsigned(register_file(C_INDEX_RESULT_ADDR)) + unsigned(assigned_block(curr_cluster_being_serviced)) * 24 + block_offset * 8);
                    block_offset <= block_offset + 1;
                    curr_state   <= block_wb;
                    WHEN block_wb =>
                    IF finished_write = '1' THEN
                        IF block_offset = "011" THEN
                            -- when finished
                            busy_bitmask(curr_cluster_being_serviced)   <= '0';
                            assigned_block(curr_cluster_being_serviced) <= (OTHERS => '0');
                            curr_state                                  <= state_3;
                            write                                       <= '0';
                        ELSE
                            write        <= '1';
                            data_value   <= payload(191 - to_integer(shift_left(block_offset, 6)) DOWNTO 191 - 63 - to_integer(shift_left(block_offset, 6)));
                            address      <= STD_LOGIC_VECTOR(unsigned(register_file(C_INDEX_RESULT_ADDR)) + unsigned(assigned_block(curr_cluster_being_serviced)) * 24 + block_offset * 8);
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
                    END IF;
                    WHEN prepare_block_wb2 =>
                    write        <= '1';
                    data_value   <= payload(191 - to_integer(shift_left(block_offset, 6)) DOWNTO 191 - 63 - to_integer(shift_left(block_offset, 6)));
                    address      <= STD_LOGIC_VECTOR(unsigned(register_file(C_INDEX_RESULT_ADDR)) + unsigned(assigned_block(curr_cluster_being_serviced)) * 24 + block_offset * 8);
                    block_offset <= block_offset + 1;
                    curr_state   <= block_wb2;
                    WHEN block_wb2 =>
                    IF finished_write = '1' THEN
                        IF block_offset = "011" THEN
                            -- when finished
                            busy_bitmask(curr_cluster_being_serviced)   <= '0';
                            assigned_block(curr_cluster_being_serviced) <= (OTHERS => '0');
                            curr_state                                  <= wait_all;
                            write                                       <= '0';
                        ELSE
                            write        <= '1';
                            data_value   <= payload(191 - to_integer(shift_left(block_offset, 6)) DOWNTO 191 - 63 - to_integer(shift_left(block_offset, 6)));
                            address      <= STD_LOGIC_VECTOR(unsigned(register_file(C_INDEX_RESULT_ADDR)) + unsigned(assigned_block(curr_cluster_being_serviced)) * 24 + block_offset * 8);
                            block_offset <= block_offset + 1;
                        END IF;
                    END IF;
                    WHEN OTHERS => NULL;
                END CASE;
            END IF;
        END IF;
    END PROCESS;
END arch_imp;