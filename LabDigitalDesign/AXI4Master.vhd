LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.axi_package.ALL;

ENTITY AXI4Master IS
    GENERIC (
        -- Users to add parameters here

        -- Parameters of Axi Master Bus Interface M00_AXI
        C_M00_AXI_START_DATA_VALUE : STD_LOGIC_VECTOR := x"AA000000";
        C_M00_AXI_TARGET_SLAVE_BASE_ADDR : STD_LOGIC_VECTOR := x"40000000";
        C_M00_AXI_ADDR_WIDTH : INTEGER := 32;
        C_M00_AXI_DATA_WIDTH : INTEGER := 32;
        C_M00_AXI_TRANSACTIONS_NUM : INTEGER := 4
    );
    PORT (

        -- INPUTS 

        read : IN STD_LOGIC;
        write : IN STD_LOGIC;
        address : IN STD_LOGIC_VECTOR(C_M00_AXI_ADDR_WIDTH - 1 DOWNTO 0);
        data_value : IN STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);

        -- OUTPUTS

        result : OUT STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);
        finished_write : OUT STD_LOGIC;
        finished_read : OUT STD_LOGIC;

        m00_axi_aclk : IN STD_LOGIC;
        m00_axi_aresetn : IN STD_LOGIC;
        m00_axi_awaddr : OUT STD_LOGIC_VECTOR(C_M00_AXI_ADDR_WIDTH - 1 DOWNTO 0);
        m00_axi_awvalid : OUT STD_LOGIC;
        m00_axi_awready : IN STD_LOGIC;
        m00_axi_wdata : OUT STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);
        m00_axi_wvalid : OUT STD_LOGIC;
        m00_axi_wready : IN STD_LOGIC;
        m00_axi_bvalid : IN STD_LOGIC;
        m00_axi_bready : OUT STD_LOGIC;
        m00_axi_araddr : OUT STD_LOGIC_VECTOR(C_M00_AXI_ADDR_WIDTH - 1 DOWNTO 0);
        m00_axi_arvalid : OUT STD_LOGIC;
        m00_axi_arready : IN STD_LOGIC;
        m00_axi_rdata : IN STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);
        m00_axi_rvalid : IN STD_LOGIC;
        m00_axi_rready : OUT STD_LOGIC
    );

END AXI4Master;

ARCHITECTURE arch_imp OF AXI4Master IS

    TYPE MasterState IS (IDLE, Write_state, Wait_state, Read_state);
    SIGNAL m_state : MasterState;

BEGIN
    master_fsm : PROCESS (m00_axi_aclk, m00_axi_aresetn)
    BEGIN
        IF rising_edge(m00_axi_aclk) THEN
            IF m00_axi_aresetn = '0' THEN
                m_state <= Idle;
            ELSE
                CASE(m_state) IS
                    WHEN Idle =>
                        finished_read <= '0';
                        finished_write <= '0';
                        m00_axi_rready <= '0';
                        m00_axi_bready <= '0';
                        m00_axi_awvalid <= '0';
                        m00_axi_wvalid <= '0';
                        m00_axi_arvalid <= '0';
                        IF Write = '1' THEN
                            m_state <= Write_state;
                            m00_axi_awvalid <= '1';
                            m00_axi_wvalid <= '1';
                            m00_axi_awaddr <= address;
                            m00_axi_wdata <= data_value;
                        ELSIF Read = '1' THEN
                            m_state <= Read_state;
                            m00_axi_araddr <= address;
                            m00_axi_arvalid <= '1';
                        END IF;
                    WHEN Write_state =>
                        IF m00_axi_awready = '1' THEN
                            m00_axi_awvalid <= '0';
                        END IF;
                        IF m00_axi_wready = '1' THEN
                            m00_axi_wvalid <= '0';
                        END IF;
                        IF m00_axi_bvalid = '1' THEN
                            m_state <= Wait_state;
                            finished_write <= '1';
                        END IF;
                    WHEN Wait_state =>
                        m00_axi_bready <= '1';
                        m_state <= Idle;
                    WHEN Read_state =>
                        IF m00_axi_arready = '1' THEN
                            m00_axi_arvalid <= '0';
                        END IF;
                        IF m00_axi_rvalid = '1' THEN
                            finished_read <= '1';
                            m00_axi_rready <= '1';
                            m_state <= Wait_state;
                            result <= m00_axi_rdata;
                        END IF;
                    WHEN OTHERS => NULL;
                END CASE;
            END IF;
        END IF;
    END PROCESS;
END arch_imp;