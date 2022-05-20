LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.axi_package.ALL;

ENTITY AXI4Slave IS
    GENERIC (
        -- Users to add parameters here

        -- User parameters ends
        -- Do not modify the parameters beyond this line
        -- Parameters of Axi Slave Bus Interface S00_AXI
        C_S00_AXI_DATA_WIDTH : INTEGER := 32;
        C_S00_AXI_ADDR_WIDTH : INTEGER := 5;
        C_NUM_REGISTERS : INTEGER := 5

    );
    PORT (

        s00_axi_aclk : IN STD_LOGIC;
        s00_axi_aresetn : IN STD_LOGIC;
        s00_axi_awaddr : IN STD_LOGIC_VECTOR(C_S00_AXI_ADDR_WIDTH - 1 DOWNTO 0);
        s00_axi_awvalid : IN STD_LOGIC;
        s00_axi_awready : OUT STD_LOGIC;
        s00_axi_wdata : IN STD_LOGIC_VECTOR(C_S00_AXI_DATA_WIDTH - 1 DOWNTO 0);
        s00_axi_wvalid : IN STD_LOGIC;
        s00_axi_wready : OUT STD_LOGIC;
        s00_axi_bvalid : OUT STD_LOGIC;
        s00_axi_bready : IN STD_LOGIC;
        s00_axi_araddr : IN STD_LOGIC_VECTOR(C_S00_AXI_ADDR_WIDTH - 1 DOWNTO 0);
        s00_axi_arvalid : IN STD_LOGIC;
        s00_axi_arready : OUT STD_LOGIC;
        s00_axi_rdata : OUT STD_LOGIC_VECTOR(C_S00_AXI_DATA_WIDTH - 1 DOWNTO 0);
        s00_axi_rvalid : OUT STD_LOGIC;
        s00_axi_rready : IN STD_LOGIC;

        index : IN STD_LOGIC_VECTOR(C_NUM_REGISTERS - 1 DOWNTO 0);
        reg_val : IN STD_LOGIC_VECTOR(C_S00_AXI_DATA_WIDTH - 1 DOWNTO 0);

        -- outputs
        register_file : OUT TReg(C_NUM_REGISTERS - 1 downto 0)
    );
END AXI4Slave;

ARCHITECTURE arch_imp OF AXI4Slave IS
    TYPE SlaveState IS (IDLE, READ, WRITE, WAIT_WREADY, WAIT_BREADY, CHECK, Finish);
    SIGNAL current_state : SlaveState;
    SIGNAL aread, awrite : STD_LOGIC_VECTOR(C_S00_AXI_ADDR_WIDTH - 1 - 2 DOWNTO 0);
     signal register_file_internal : TReg(C_NUM_REGISTERS - 1 downto 0);
BEGIN

    aread <= s00_axi_araddr(C_S00_AXI_ADDR_WIDTH - 1 DOWNTO 2);
    awrite <= s00_axi_awaddr(C_S00_AXI_ADDR_WIDTH - 1 DOWNTO 2);

	register_file <= register_file_internal;

    PROCESS (s00_axi_aclk, s00_axi_aresetn)
    BEGIN
        IF rising_edge(s00_axi_aclk) THEN

            s00_axi_awready <= '0';
            s00_axi_arready <= '0';
            s00_axi_wready <= '0';
            s00_axi_rvalid <= '0';
            s00_axi_bvalid <= '0';

            if to_integer(unsigned(index)) < C_NUM_REGISTERS then
                register_file_internal(to_integer(unsigned(index))) <= reg_val;
            end if;


            IF s00_axi_aresetn = '0' THEN
                current_state <= Idle;
            ELSE
                CASE(current_state) IS
                    WHEN Idle =>
                    s00_axi_bvalid <= '0';
                    IF s00_axi_awvalid = '1' THEN
                        current_state <= Write;
                        s00_axi_awready <= '1';
                    ELSIF s00_axi_arvalid = '1' THEN
                        current_state <= Read;
                        s00_axi_arready <= '1';
                    END IF;

                    WHEN Write =>
                    s00_axi_wready <= '1';
                    IF s00_axi_wvalid = '1' THEN
                        current_state <= Finish;
                        register_file_internal(to_integer(unsigned(awrite))) <= s00_axi_wdata;
                    END IF;

                    WHEN Finish =>
                    s00_axi_wready <= '0';
                    s00_axi_bvalid <= '1';
                    IF s00_axi_bready = '1' THEN
                        current_state <= Idle;
                    END IF;

                    WHEN Read =>
                    s00_axi_rvalid <= '1';
                    s00_axi_rdata <= register_file_internal(to_integer(unsigned(aread)));
                    IF s00_axi_rready = '1' THEN
                        current_state <= Idle;
                    END IF;

                    WHEN OTHERS => NULL;
                END CASE;
            END IF;
        END IF;
    END PROCESS;

END arch_imp;