LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.common_utils_pkg.ALL;

LIBRARY UNISIM;
USE UNISIM.vcomponents.ALL;

LIBRARY UNIMACRO;
USE UNIMACRO.vcomponents.ALL;
ENTITY FIFOController IS
    GENERIC (
        -- Parameters of Axi Master Bus Interface M00_AXI
        C_M00_AXI_ADDR_WIDTH : INTEGER := 32;
        C_M00_AXI_DATA_WIDTH : INTEGER := 64
    );
    PORT (
        clk               : IN STD_LOGIC;
        nReset            : IN STD_LOGIC;

        n_blocks          : IN unsigned(7 DOWNTO 0);
        start             : IN STD_LOGIC;

        read              : IN STD_LOGIC;
        finished_read     : OUT STD_LOGIC;

        -- Towards Axi Master
        read_axi          : OUT STD_LOGIC;
        finished_read_axi : IN STD_LOGIC;
        address_axi       : INOUT STD_LOGIC_VECTOR(C_M00_AXI_ADDR_WIDTH - 1 DOWNTO 0);
        result_axi        : IN STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);

        result            : OUT STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);
        block_address     : IN STD_LOGIC_VECTOR(C_M00_AXI_ADDR_WIDTH - 1 DOWNTO 0)
        --debug 
        --out_state         : OUT fifo_controller_state_axi;
        --rden_out          : OUT STD_LOGIC;
        --rst_out           : OUT STD_LOGIC;
        --is_resetting_out  : OUT STD_LOGIC;
        --wren_out          : OUT STD_LOGIC;
        --curr_block_out    : OUT unsigned(7 DOWNTO 0);
        --block_offset_out  : OUT unsigned(2 DOWNTO 0);
        --DI_out            : OUT STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0);
        --DO_out            : OUT STD_LOGIC_VECTOR(C_M00_AXI_DATA_WIDTH - 1 DOWNTO 0)

    );
END FIFOController;

ARCHITECTURE arch_imp OF FIFOController IS
    SIGNAL ALMOSTEMPTY    : STD_LOGIC;
    SIGNAL ALMOSTFULL     : STD_LOGIC;
    SIGNAL DO             : STD_LOGIC_VECTOR(63 DOWNTO 0);
    SIGNAL DOP            : STD_LOGIC_VECTOR(7 DOWNTO 0); --unused
    SIGNAL EMPTY          : STD_LOGIC;
    SIGNAL FULL           : STD_LOGIC;
    SIGNAL RDCOUNT        : STD_LOGIC_VECTOR(8 DOWNTO 0);
    SIGNAL RDERR          : STD_LOGIC;
    SIGNAL WRCOUNT        : STD_LOGIC_VECTOR(8 DOWNTO 0);
    SIGNAL WRERR          : STD_LOGIC;
    SIGNAL DI             : STD_LOGIC_VECTOR(63 DOWNTO 0);
    SIGNAL DIP            : STD_LOGIC_VECTOR(7 DOWNTO 0); --unused
    SIGNAL RDEN           : STD_LOGIC;
    SIGNAL WREN           : STD_LOGIC;
    SIGNAL rst            : STD_LOGIC                 := '0';
    SIGNAL curr_state_axi : fifo_controller_state_axi := Reset_fifo;

    SIGNAL curr_block     : unsigned(7 DOWNTO 0);
    SIGNAL block_offset   : unsigned(2 DOWNTO 0);
    SIGNAL is_resetting   : STD_LOGIC := '0';

BEGIN

    --curr_block_out   <= curr_block;
    --block_offset_out <= block_offset;
    --out_state        <= curr_state_axi;
    --rden_out         <= rden;
    --wren_out         <= wren;
    --DI_out           <= DI;
    --DO_out           <= DO;
    --rst_out          <= rst;
    --is_resetting_out <= is_resetting;

    -- FIFO_SYNC_MACRO: Synchronous First-In, First-Out (FIFO) RAM Buffer
    --                  Artix-7
    -- Xilinx HDL Language Template, version 2020.2

    -- Note -  This Unimacro model assumes the port directions to be "downto". 
    --         Simulation of this model with "to" in the port directions could lead to erroneous results.

    -----------------------------------------------------------------
    -- DATA_WIDTH | FIFO_SIZE | FIFO Depth | RDCOUNT/WRCOUNT Width --
    -- ===========|===========|============|=======================--
    --   37-72    |  "36Kb"   |     512    |         9-bit         --
    --   19-36    |  "36Kb"   |    1024    |        10-bit         --
    --   19-36    |  "18Kb"   |     512    |         9-bit         --
    --   10-18    |  "36Kb"   |    2048    |        11-bit         --
    --   10-18    |  "18Kb"   |    1024    |        10-bit         --
    --    5-9     |  "36Kb"   |    4096    |        12-bit         --
    --    5-9     |  "18Kb"   |    2048    |        11-bit         --
    --    1-4     |  "36Kb"   |    8192    |        13-bit         --
    --    1-4     |  "18Kb"   |    4096    |        12-bit         --
    -----------------------------------------------------------------

    wren             <= finished_read_axi AND (NOT is_resetting);
    DI               <= result_axi;
    rden             <= read AND (NOT empty) AND (NOT is_resetting);
    result           <= DO;

    delay_read : PROCESS (clk)
    BEGIN
        IF rising_edge(clk) THEN
            finished_read <= '0';
            IF rden = '1' THEN
                finished_read <= '1';
            END IF;
        END IF;
    END PROCESS;

    FIFO_SYNC_MACRO_inst : FIFO_SYNC_MACRO
    GENERIC MAP(
        DEVICE              => "7SERIES", -- Target Device: "VIRTEX5, "VIRTEX6", "7SERIES" 
        ALMOST_FULL_OFFSET  => X"0080",   -- Sets almost full threshold
        ALMOST_EMPTY_OFFSET => X"0080",   -- Sets the almost empty threshold
        DATA_WIDTH          => 64,        -- Valid values are 1-72 (37-72 only valid when FIFO_SIZE="36Kb")
        FIFO_SIZE           => "36Kb")    -- Target BRAM, "18Kb" or "36Kb" 
    PORT MAP(
        ALMOSTEMPTY => ALMOSTEMPTY, -- 1-bit output almost empty
        ALMOSTFULL  => ALMOSTFULL,  -- 1-bit output almost full
        DO          => DO,          -- Output data, width defined by DATA_WIDTH parameter
        EMPTY       => EMPTY,       -- 1-bit output empty
        FULL        => FULL,        -- 1-bit output full
        RDCOUNT     => RDCOUNT,     -- Output read count, width determined by FIFO depth
        RDERR       => RDERR,       -- 1-bit output read error
        WRCOUNT     => WRCOUNT,     -- Output write count, width determined by FIFO depth
        WRERR       => WRERR,       -- 1-bit output write error
        CLK         => CLK,         -- 1-bit input clock
        DI          => DI,          -- Input data, width defined by DATA_WIDTH parameter
        RDEN        => RDEN,        -- 1-bit input read enable
        RST         => RST,         -- 1-bit input reset
        WREN        => WREN         -- 1-bit input write enable
    );
    -- End of FIFO_SYNC_MACRO_inst instantiation
    controller_axi_side : PROCESS (clk, nReset)
        VARIABLE counter : unsigned(31 DOWNTO 0) := (OTHERS => '0');
    BEGIN
        IF rising_edge(clk) THEN
            RST <= '0';
            IF nReset = '0' THEN
                curr_state_axi <= Reset_fifo;
                curr_block     <= (OTHERS => '0');
                block_offset   <= (OTHERS => '0');
                counter := (OTHERS        => '0');
                read_axi     <= '0';
                address_axi  <= (OTHERS => '0');
                is_resetting <= '1';
                RST          <= '1';
            ELSE
                CASE curr_state_axi IS
                    WHEN Reset_fifo =>
                        is_resetting <= '1';
                        IF counter = x"00000006" THEN
                            curr_state_axi <= Pre_Idle_fifo; -- to give extra cycle rst 0
                            RST            <= '0';
                        END IF;
                        RST <= '1';
                        counter := counter + 1;
                    WHEN Pre_Idle_fifo =>
                        read_axi    <= '0';
                        address_axi <= (OTHERS => '0');
                        IF start = '0' THEN
                            curr_state_axi <= Idle_fifo;
                        END IF;
                    WHEN Idle_fifo =>
                        is_resetting <= '0';
                        curr_block   <= (OTHERS => '0');
                        read_axi     <= '0';
                        address_axi  <= (OTHERS => '0');
                        counter := (OTHERS      => '0');
                        block_offset <= (OTHERS => '0');
                        IF start = '1' THEN
                            curr_state_axi <= block_fetch_fifo;
                        END IF;
                    WHEN block_fetch_fifo =>
                        IF curr_block = n_blocks THEN
                            curr_state_axi <= Pre_Idle_fifo;
                        ELSE
                            address_axi    <= STD_LOGIC_VECTOR(unsigned(block_address) + resize(curr_block, 16) * 64 + resize(block_offset, 8) * 8);
                            read_axi       <= '1';
                            curr_state_axi <= fetch_sub_blocks;
                        END IF;
                    WHEN fetch_sub_blocks =>
                        read_axi <= '1';
                        IF finished_read_axi = '1' THEN
                            address_axi <= STD_LOGIC_VECTOR(unsigned(address_axi) + 8);
                            IF full = '0' THEN
                                block_offset <= block_offset + 1;
                                IF block_offset = "111" THEN
                                    curr_block     <= curr_block + 1;
                                    curr_state_axi <= block_fetch_fifo;
                                    read_axi       <= '0';
                                END IF;
                            ELSE
                                read_axi <= '0';
                            END IF;
                        END IF;
                    WHEN OTHERS => NULL;
                END CASE;
            END IF;
        END IF;
    END PROCESS;

END arch_imp;