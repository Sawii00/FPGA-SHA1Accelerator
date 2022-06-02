LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.common_utils_pkg.ALL;

-- TODO: - what about timeout if there is no way with the counter to yield such hash
--       - 

ENTITY TopLevel IS
    GENERIC (
        -- Users to add parameters here

        -- User parameters ends
        -- Do not modify the parameters beyond this line
        -- Parameters of Axi Slave Bus Interface S00_AXI
        C_S00_AXI_DATA_WIDTH : INTEGER := 32;
        C_S00_AXI_ADDR_WIDTH : INTEGER := 5;
        C_NUM_REGISTERS : INTEGER := 9;

        -- Parameters of Axi Master Bus Interface M00_AXI
        C_M00_AXI_ADDR_WIDTH : INTEGER := 32;
        C_M00_AXI_DATA_WIDTH : INTEGER := 64;

        CLUSTER_COUNT : INTEGER := 2;
        N_HASHERS : INTEGER := 2
    );
    PORT (

        clk : IN STD_LOGIC;
        nReset : IN STD_LOGIC;

        irq : OUT STD_LOGIC;
        
        reset_irq_out : out std_logic;

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
    CONSTANT C_INDEX_BLOCK_ADDRESS : INTEGER := 0;
    CONSTANT C_INDEX_N_BLOCKS : INTEGER := 1;
    CONSTANT C_INDEX_DIFFICULTY : INTEGER := 2;
    CONSTANT C_INDEX_START : INTEGER := 3;
    CONSTANT C_INDEX_STOP : INTEGER := 4;
    CONSTANT C_INDEX_DONE : INTEGER := 5;
    CONSTANT C_INDEX_RESULT_ADDR : INTEGER := 6;
    CONSTANT C_INDEX_IRQ_ENABLE : INTEGER := 7;
    CONSTANT C_INDEX_IRQ_TOGGLE : INTEGER := 8;

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
    SIGNAL reg_val_sig : STD_LOGIC_VECTOR(C_S00_AXI_DATA_WIDTH - 1 DOWNTO 0);

    SIGNAL cluster_done_signal : STD_LOGIC_VECTOR(CLUSTER_COUNT - 1 DOWNTO 0);
    SIGNAL cluster_hashes_signal : ARR_160(CLUSTER_COUNT - 1 DOWNTO 0);
    SIGNAL cluster_nonces_signal : ARR_32(CLUSTER_COUNT - 1 DOWNTO 0);
    -- OUTPUT TO CLUSTER
    SIGNAL cluster_blocks_signal : ARR_512(CLUSTER_COUNT - 1 DOWNTO 0);
    SIGNAL cluster_start_signal : STD_LOGIC_VECTOR(CLUSTER_COUNT - 1 DOWNTO 0);
    SIGNAL reset_IRQ : STD_LOGIC;
    signal fsm_irq : std_logic;

BEGIN
    s00_axi_rresp <= (OTHERS => '0'); -- "OKAY"
    s00_axi_bresp <= (OTHERS => '0'); -- "OKAY"

    m00_axi_awprot <= (OTHERS => '0');
    m00_axi_arprot <= (OTHERS => '0');
    m00_axi_wstrb <= (OTHERS => '1');

    reset_irq_out <= reset_irq;

    handle_irq : process (CLK, nReset)
    begin 
    if nReset = '0' then 
        irq <= '0';
    elsif rising_edge(clk) then 
        if fsm_irq = '1' then 
            irq  <= '1';
        end if;
        if reset_irq = '1' then 
            irq <= '0';
        end if;
    end if;
    end process;


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
            reset_irq => reset_irq,
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

    fsm_comp : ENTITY work.FSM
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

            fsm_irq => fsm_irq,

            -- outputs 
            read => read_sig,
            write => write_sig,
            address => address_sig,
            data_value => data_value_sig,

            index => index_sig,
            reg_val => reg_val_sig,
            cluster_done => cluster_done_signal,
            cluster_hashes => cluster_hashes_signal,
            cluster_nonces => cluster_nonces_signal,
            cluster_blocks => cluster_blocks_signal,
            cluster_start => cluster_start_signal
        );

    clusters : FOR i IN 0 TO CLUSTER_COUNT - 1 GENERATE
        hasher : ENTITY work.Cluster
            GENERIC MAP(N_HASHERS => N_HASHERS)
            PORT MAP(
                clk => clk,
                nReset => nReset,

                input_block => cluster_blocks_signal(i),
                start => cluster_start_signal(i),
                stop => register_file_sig(C_INDEX_STOP)(0),
                difficulty => register_file_sig(C_INDEX_DIFFICULTY),
                done => cluster_done_signal(i),
                hash => cluster_hashes_signal(i),
                nonce => cluster_nonces_signal(i)
            );
    END GENERATE clusters;

END arch_imp;