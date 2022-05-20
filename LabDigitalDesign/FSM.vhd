LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.axi_package.ALL;

ENTITY FSM IS
    GENERIC (
        -- Users to add parameters here

        -- User parameters ends
        -- Do not modify the parameters beyond this line
        -- Parameters of Axi Slave Bus Interface S00_AXI
        C_S00_AXI_DATA_WIDTH : INTEGER := 32;
        C_S00_AXI_ADDR_WIDTH : INTEGER := 5;
        C_NUM_REGISTERS : INTEGER := 5;
        C_INDEX_ADDRESS : Integer := 0;
        C_INDEX_REQVALUE : Integer := 1;
        C_INDEX_START : Integer := 2;
        C_INDEX_DONE : Integer := 3;
        C_INDEX_MODIFIED : Integer := 4;


        -- Parameters of Axi Master Bus Interface M00_AXI
        C_M00_AXI_START_DATA_VALUE : STD_LOGIC_VECTOR := x"AA000000";
        C_M00_AXI_TARGET_SLAVE_BASE_ADDR : STD_LOGIC_VECTOR := x"40000000";
        C_M00_AXI_ADDR_WIDTH : INTEGER := 32;
        C_M00_AXI_DATA_WIDTH : INTEGER := 32;
        C_M00_AXI_TRANSACTIONS_NUM : INTEGER := 4
    );
    PORT (

        -- inputs
        nReset : IN STD_LOGIC;
        clk : IN STD_LOGIC;

        register_file : IN TReg;

        result : IN STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);
        finished_write : IN STD_LOGIC;
        finished_read : IN STD_LOGIC;

        -- outputs 
        read : OUT STD_LOGIC;
        write : OUT STD_LOGIC;
        address : OUT STD_LOGIC_VECTOR(C_M00_AXI_ADDR_WIDTH - 1 DOWNTO 0);
        data_value : OUT STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);

        index : out STD_LOGIC_VECTOR(C_NUM_REGISTERS - 1 DOWNTO 0);
        reg_val : out STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0)

    );
END FSM;

ARCHITECTURE arch_imp OF FSM IS
    TYPE TReg IS ARRAY (C_NUM_REGISTERS - 1 DOWNTO 0) OF STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);

    TYPE FSMState IS (IDLE, READ_state, WRITE_state, WAIT_WREADY, WAIT_BREADY, CHECK, Finish);
    SIGNAL m_state : FSMState;

BEGIN

 

    fsm : PROCESS (clk, nReset)
    BEGIN
        IF rising_edge(clk) THEN
            IF nReset = '0' THEN
                m_state <= Idle;
            ELSE
                CASE(m_state) IS
                    WHEN Idle =>
                    address <= (OTHERS => '0');
                    data_value <= (OTHERS => '0');
                    read <= '0';
                    write <= '0';
                    index <= std_logic_vector(to_unsigned(C_INDEX_DONE, index'length));
                    reg_val <= x"00000001";
                    IF register_file(C_INDEX_START)(0) = '1' THEN
                        index <= std_logic_vector(to_unsigned(C_INDEX_DONE, index'length));
                        reg_val <= x"00000000";
                        address <= register_file(C_INDEX_ADDRESS);
                        read <= '1';
                        IF finished_read = '1' THEN
                            index <= std_logic_vector(to_unsigned(C_INDEX_START, index'length));
                            reg_val <= x"00000000";
                            m_state <= Check;
                            read <= '0';
                        END IF;
                    END IF;

                    WHEN Check =>
                    IF result = register_file(C_INDEX_REQVALUE) THEN
                        m_state <= Idle;
                        index <= std_logic_vector(to_unsigned(C_INDEX_MODIFIED, index'length));
                        reg_val <= x"00000000";
                    ELSE
                        m_state <= WRITE_state;
                    END IF;

                    WHEN WRITE_state =>
                    address <= register_file(C_INDEX_ADDRESS);
                    write <= '1';
                    data_value <= register_file(C_INDEX_REQVALUE);
                    IF finished_write = '1' THEN
                        m_state <= Idle;
                        write <= '0';
                        index <= std_logic_vector(to_unsigned(C_INDEX_MODIFIED, index'length));
                        reg_val <= x"00000001";
                    END IF;
                    WHEN OTHERS => NULL;
                END CASE;

            END IF;
        END IF;
    END PROCESS;
END arch_imp;