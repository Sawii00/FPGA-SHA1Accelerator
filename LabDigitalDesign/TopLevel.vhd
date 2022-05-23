LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.axi_package.ALL;

ENTITY TopLevel IS
    GENERIC (
        -- Users to add parameters here

        -- User parameters ends
        -- Do not modify the parameters beyond this line
        -- Parameters of Axi Slave Bus Interface S00_AXI
        C_S00_AXI_DATA_WIDTH : INTEGER := 32;
        C_S00_AXI_ADDR_WIDTH : INTEGER := 5;
        C_NUM_REGISTERS : INTEGER := 7;

        -- Parameters of Axi Master Bus Interface M00_AXI
        C_M00_AXI_ADDR_WIDTH : INTEGER := 32;
        C_M00_AXI_DATA_WIDTH : INTEGER := 64;

        CLUSTER_COUNT : INTEGER := 2
    );
    PORT (

        clk : IN STD_LOGIC;
        nReset : IN STD_LOGIC;

        s00_axi_awaddr : IN STD_LOGIC_VECTOR(C_S00_AXI_ADDR_WIDTH - 1 DOWNTO 0);
        s00_axi_awprot : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
        s00_axi_awvalid : IN STD_LOGIC;
        s00_axi_awready : OUT STD_LOGIC;
        s00_axi_wdata : IN STD_LOGIC_VECTOR(C_S00_AXI_DATA_WIDTH - 1 DOWNTO 0);
        s00_axi_wstrb : IN STD_LOGIC_VECTOR((C_S00_AXI_DATA_WIDTH/8) - 1 DOWNTO 0);
        s00_axi_wvalid : IN STD_LOGIC;
        s00_axi_wready : OUT STD_LOGIC;
        s00_axi_bresp : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
        s00_axi_bvalid : OUT STD_LOGIC;
        s00_axi_bready : IN STD_LOGIC;
        s00_axi_araddr : IN STD_LOGIC_VECTOR(C_S00_AXI_ADDR_WIDTH - 1 DOWNTO 0);
        s00_axi_arprot : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
        s00_axi_arvalid : IN STD_LOGIC;
        s00_axi_arready : OUT STD_LOGIC;
        s00_axi_rdata : OUT STD_LOGIC_VECTOR(C_S00_AXI_DATA_WIDTH - 1 DOWNTO 0);
        s00_axi_rresp : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
        s00_axi_rvalid : OUT STD_LOGIC;
        s00_axi_rready : IN STD_LOGIC;

        m00_axi_awaddr : OUT STD_LOGIC_VECTOR(C_M00_AXI_ADDR_WIDTH - 1 DOWNTO 0);
        m00_axi_awprot : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
        m00_axi_awvalid : OUT STD_LOGIC;
        m00_axi_awready : IN STD_LOGIC;
        m00_axi_wdata : OUT STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);
        m00_axi_wstrb : OUT STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH/8 - 1 DOWNTO 0);
        m00_axi_wvalid : OUT STD_LOGIC;
        m00_axi_wready : IN STD_LOGIC;
        m00_axi_bresp : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
        m00_axi_bvalid : IN STD_LOGIC;
        m00_axi_bready : OUT STD_LOGIC;
        m00_axi_araddr : OUT STD_LOGIC_VECTOR(C_M00_AXI_ADDR_WIDTH - 1 DOWNTO 0);
        m00_axi_arprot : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
        m00_axi_arvalid : OUT STD_LOGIC;
        m00_axi_arready : IN STD_LOGIC;
        m00_axi_rdata : IN STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);
        m00_axi_rresp : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
        m00_axi_rvalid : IN STD_LOGIC;
        m00_axi_rready : OUT STD_LOGIC
    );
END TopLevel;

ARCHITECTURE arch_imp OF TopLevel IS

    SIGNAL register_file_sig : TReg(C_NUM_REGISTERS - 1 DOWNTO 0);

    SIGNAL result_sig : STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL finished_write_sig : STD_LOGIC;
    SIGNAL finished_read_sig : STD_LOGIC;

    -- outputs 
    SIGNAL read_sig : STD_LOGIC;
    SIGNAL write_sig : STD_LOGIC;
    SIGNAL address_sig : STD_LOGIC_VECTOR(C_M00_AXI_ADDR_WIDTH - 1 DOWNTO 0);
    SIGNAL data_value_sig : STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);

    SIGNAL index_sig : STD_LOGIC_VECTOR(C_NUM_REGISTERS - 1 DOWNTO 0);
    SIGNAL reg_val_sig : STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);

BEGIN
    s00_axi_rresp <= (OTHERS => '0'); -- "OKAY"
    s00_axi_bresp <= (OTHERS => '0'); -- "OKAY"

    m00_axi_awprot <= (OTHERS => '0');
    m00_axi_arprot <= (OTHERS => '0');
    m00_axi_wstrb <= (OTHERS => '1');

    slave : ENTITY work.AXI4Slave
        GENERIC MAP(
            C_S00_AXI_DATA_WIDTH => C_S00_AXI_DATA_WIDTH,
            C_S00_AXI_ADDR_WIDTH => C_S00_AXI_ADDR_WIDTH,
            C_NUM_REGISTERS => C_NUM_REGISTERS
        )
        PORT MAP(

            s00_axi_aclk => clk,
            s00_axi_aresetn => nReset,
            s00_axi_awaddr => s00_axi_awaddr,
            s00_axi_awvalid => s00_axi_awvalid,
            s00_axi_awready => s00_axi_awready,
            s00_axi_wdata => s00_axi_wdata,
            s00_axi_wvalid => s00_axi_wvalid,
            s00_axi_wready => s00_axi_wready,
            s00_axi_bvalid => s00_axi_bvalid,
            s00_axi_bready => s00_axi_bready,
            s00_axi_araddr => s00_axi_araddr,
            s00_axi_arvalid => s00_axi_arvalid,
            s00_axi_arready => s00_axi_arready,
            s00_axi_rdata => s00_axi_rdata,
            s00_axi_rvalid => s00_axi_rvalid,
            s00_axi_rready => s00_axi_rready,

            index => index_sig,
            reg_val => reg_val_sig,

            -- outputs
            register_file => register_file_sig
        );

    master : ENTITY work.AXI4Master
        GENERIC MAP(
            -- Parameters of Axi Master Bus Interface M00_AXI
            C_M00_AXI_ADDR_WIDTH => C_M00_AXI_ADDR_WIDTH,
            C_M00_AXI_DATA_WIDTH => C_M00_AXI_DATA_WIDTH
        )
        PORT MAP(

            read => read_sig,
            write => write_sig,
            address => address_sig,
            data_value => data_value_sig,

            -- OUTPUTS

            result => result_sig,
            finished_write => finished_write_sig,
            finished_read => finished_read_sig,

            m00_axi_aclk => clk,
            m00_axi_aresetn => nReset,
            m00_axi_awaddr => m00_axi_awaddr,
            m00_axi_awvalid => m00_axi_awvalid,
            m00_axi_awready => m00_axi_awready,
            m00_axi_wdata => m00_axi_wdata,
            m00_axi_wvalid => m00_axi_wvalid,
            m00_axi_wready => m00_axi_wready,
            m00_axi_bvalid => m00_axi_bvalid,
            m00_axi_bready => m00_axi_bready,
            m00_axi_araddr => m00_axi_araddr,
            m00_axi_arvalid => m00_axi_arvalid,
            m00_axi_arready => m00_axi_arready,
            m00_axi_rdata => m00_axi_rdata,
            m00_axi_rvalid => m00_axi_rvalid,
            m00_axi_rready => m00_axi_rready

        );

    fsm_comp : entity work.FSM
        GENERIC MAP(
            C_M00_AXI_ADDR_WIDTH => C_M00_AXI_ADDR_WIDTH,
            C_M00_AXI_DATA_WIDTH => C_M00_AXI_DATA_WIDTH,
            C_S00_AXI_DATA_WIDTH => C_S00_AXI_DATA_WIDTH,
            C_S00_AXI_ADDR_WIDTH => C_S00_AXI_ADDR_WIDTH,
            C_NUM_REGISTERS => C_NUM_REGISTERS,
            CLUSTER_COUNT => CLUSTER_COUNT
        )
        PORT MAP(
            nReset => nReset,
            clk => clk,

            register_file => register_file_sig,

            result => result_sig,
            finished_write => finished_write_sig,
            finished_read => finished_read_sig,

            -- outputs 
            read => read_sig,
            write => write_sig,
            address => address_sig,
            data_value => data_value_sig,

            index => index_sig,
            reg_val => reg_val_sig
        );

    END arch_imp;