#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>
#include <unistd.h>
#include "OverlayControl.h"
#include <time.h>
#include "sha.h"


// Structure used to pass commands between user-space and kernel-space.
struct user_message {
    uint32_t block_address_base;
    uint32_t n_blocks;
    uint32_t difficulty;
    uint32_t result_address;
};


extern "C"
{
#include <libxlnk_cma.h>
}
// Base address for the mapping of (all) peripherals
#define BASE_MAP  0x43C00000

#define DEFAULT_MAX_BLOCKS 16
#define DEFAULT_N_EXPERIMENTS 5 
#define DEFAULT_MAX_DIFFICULTY 16 

#define FUNC_TESTING 0
#define DEBUG 0
#define DUMP 0
#define ACCELERATOR 1

const char* DRIVER_NAME="/dev/hasher";
int driver;

struct experiment_stats
{
    double time_taken_ms;
    uint64_t hash_per_sec;
};

uint64_t _bswap64(uint64_t val)
{
    uint64_t res = 0;
    res |= ((val & 0xff) << 56);
    res |= ((val & 0xff00) << 40);
    res |= ((val & 0xff0000) << 24);
    res |= ((val & 0xff000000) << 8);
    res |= ((val & 0xff00000000) >> 8);
    res |= ((val & 0xff0000000000) >> 24);
    res |= ((val & 0xff000000000000) >> 40);
    res |= ((val & 0xff00000000000000) >> 56);
    return res;
}

uint32_t _bswap32(uint32_t val)
{
    uint32_t res = 0;
    res |= ((val & 0xff) << 24);
    res |= ((val & 0xff00) << 8);
    res |= ((val & 0xff0000) >> 8);
    res |= ((val & 0xff000000) >> 24);
    return res;
}

struct hasher_result
{
    uint32_t b;
    uint32_t a;
    uint32_t d;
    uint32_t c;
    uint32_t nonce;
    uint32_t e;
}__attribute((packed))__;


uint64_t compute_avg_hash_per_second(uint8_t *addr, uint32_t n_blocks, double time_taken_ms)
{
    uint64_t total_nonces = 0;
    for(uint32_t i = 0; i < n_blocks; ++i)
    {
        struct hasher_result res = *((struct hasher_result*)(addr + 24*i));
        total_nonces += res.nonce;
    }

    return (double)total_nonces * 1000 / time_taken_ms;
}

void print_memory_bytes(uint8_t* arr, uint32_t count)
{
    for(uint32_t i = 0; i < count; ++i)
    {
        printf("%02x", arr[i]);
        if((i + 1) % 64 == 0)printf("\n");
    }
    printf("\n");
}

void print_hash_nonces(uint32_t* start_addr, uint8_t block_count)
{
    for(uint32_t b = 0; b < block_count; ++b)
    {
        printf("BLOCK: %u\n", b);
        printf("\tHASH: ");
        struct hasher_result res = *(struct hasher_result*)((uint8_t*)start_addr +24*b);
        printf("%08x%08x%08x%08x%08x",res.a, res.b, res.c, res.d, res.e);
        printf("\tNONCE: %08x\n", res.nonce);
    }
}

void test_device()
{

    uint32_t n_blocks = 2;
    uint32_t difficulty = 0xFFFFF000;


    uint32_t * virtual_addr = (uint32_t *) cma_alloc(1024, 0);
    if(!virtual_addr)
    {
        printf("Error cma_alloc\n"); 
        exit(-1);
    }

    uint32_t *physical_addr = (uint32_t *)cma_get_phy_addr(virtual_addr);
    printf("Physical Addr: %x\n", (uint32_t)physical_addr);


    uint64_t *start_address = (uint64_t*)virtual_addr;
    uint64_t val;
    for(uint32_t i = 0; i < n_blocks; ++i)
    {
        if (i == 0)
            val = 0xFFFFFFFFFFFFFFFF;
        else
            val = 0x0F0F0F0F0F0F0F0F;
        for(uint32_t j = 0; j < 8; ++j)
        {
            *(start_address + i * 8 + j) = val; 
        }

    }

    print_memory_bytes((uint8_t*)start_address, 64 * n_blocks);



    clock_t diff;
    clock_t start = clock();

    struct user_message mex = {(uint32_t)physical_addr, n_blocks, difficulty, (uint32_t)((uint8_t*)physical_addr + 64*n_blocks + 64)};

    uint32_t driver_err = read(driver, (void*)&mex, sizeof(mex));
    if(driver_err)
    {
        printf("Invalid read from driver\n");
        exit(-1);
    }

    diff = clock() - start;

    double msec = ((double)diff / CLOCKS_PER_SEC) * 1000;
    printf("\nDONE EXPERIMENT\n");
    printf("Time: %f (ms)", msec);
    print_hash_nonces((uint32_t*)((uint8_t*)virtual_addr + 64*n_blocks + 64), n_blocks);


    cma_free(virtual_addr);

}


struct experiment_stats run_experiment(uint32_t n_blocks, uint32_t difficulty)
{


    struct experiment_stats res;
#if DEBUG
    printf("-----------------------------------------------\n\n");
#endif
    uint32_t * virtual_addr = (uint32_t *) cma_alloc(n_blocks * 64 + n_blocks * 24 + 1024, 0);
    if(!virtual_addr)
    {
        printf("Error cma_alloc\n"); 
        exit(-1);
    }

    uint32_t *physical_addr = (uint32_t *)cma_get_phy_addr(virtual_addr);
#if DEBUG
    printf("Physical Addr: %x\n", (uint32_t)physical_addr);
#endif


    uint64_t *start_address = (uint64_t*)virtual_addr;
    for(uint32_t i = 0; i < n_blocks; ++i)
    {
        for(uint32_t j = 0; j < 8; ++j)
        {
            *(start_address + i * 8 + j) = rand(); 
        }

    }

#if DEBUG
    print_memory_bytes((uint8_t*)start_address, 64);
#endif

    struct user_message mex = {(uint32_t)physical_addr, n_blocks, difficulty, (uint32_t)((uint8_t*)physical_addr + 64*n_blocks + 64)};

    clock_t diff;
    clock_t start = clock();

    uint32_t driver_err = read(driver, (void*)&mex, sizeof(mex));
    if(driver_err)
    {
        printf("Invalid read from driver\n");
        exit(-1);
    }

    diff = clock() - start;

    double msec = ((double)diff / CLOCKS_PER_SEC) * 1000;
#if DEBUG
    printf("\nDONE EXPERIMENT\n");
    printf("Time: %f (ms)", msec);
    print_hash_nonces((uint32_t*)((uint8_t*)virtual_addr + n_blocks * 64 + 64), n_blocks);
#endif

    res.time_taken_ms = msec;
    res.hash_per_sec = compute_avg_hash_per_second((uint8_t*)virtual_addr + n_blocks * 64 + 64, n_blocks, msec);

    cma_free(virtual_addr);
    return res;
}

struct hasher_result compute_hash_block_cpu(uint8_t* addr, uint32_t difficulty)
{
    uint32_t nonce = 0;
    struct hasher_result final_result;
    while(1)
    {
        *(uint32_t*)(addr + 60) = nonce;
        struct internal_state res = sha1(addr, 64);
        if(!(res.A & difficulty))
        {
            //Nonce found
            final_result.a = res.A;
            final_result.b = res.B;
            final_result.c = res.C;
            final_result.d = res.D;
            final_result.e = res.E;
            final_result.nonce = nonce;
            break;
        }
        nonce += 1;
    }
    return final_result;
}


struct experiment_stats run_experiment_cpu(uint32_t n_blocks, uint32_t difficulty)
{

    struct experiment_stats res;
#if DEBUG
    printf("-----------------------------------------------\n\n");
#endif
    uint32_t * virtual_addr = (uint32_t *) cma_alloc(n_blocks * 64 + n_blocks * 24 + 1024, 0);
    if(!virtual_addr)
    {
        printf("Error cma_alloc\n"); 
        exit(-1);
    }

    uint64_t *start_address = (uint64_t*)virtual_addr;
    for(uint32_t i = 0; i < n_blocks; ++i)
    {
        for(uint32_t j = 0; j < 8; ++j)
        {
            *(start_address + i * 8 + j) = rand(); 
        }

    }

#if DEBUG
    print_memory_bytes((uint8_t*)start_address, 64);
#endif


    clock_t diff = 0;
    uint32_t tot_nonces = 0;
    clock_t start = clock();

    for(uint32_t i = 0; i < n_blocks; ++i)
    {
        start = clock();
        struct hasher_result res = compute_hash_block_cpu((uint8_t*)start_address + 64*i, difficulty);
        diff += (clock() - start);
        tot_nonces += res.nonce;
    }


    double msec = ((double)diff / CLOCKS_PER_SEC) * 1000;
#if DEBUG
    printf("\nDONE EXPERIMENT\n");
    printf("Time: %f (ms)", msec);
#endif

    res.time_taken_ms = msec;
    res.hash_per_sec = (double)tot_nonces * 1000 / msec;

    cma_free(virtual_addr);
    return res;
}


int main(int argc, char ** argv)
{

    driver = open(DRIVER_NAME, O_RDWR);
    if(driver == -1)
    {
        printf("Error opening the driver\n");
        exit(-1);
    }
#if DUMP
    freopen("log.txt", "w", stdout);
#endif

    uint32_t MAX_BLOCKS;
    uint32_t N_EXPERIMENTS;
    uint32_t MAX_DIFFICULTY;

    if (argc == 1)
    {
        MAX_BLOCKS = DEFAULT_MAX_BLOCKS;
        N_EXPERIMENTS = DEFAULT_N_EXPERIMENTS;
        MAX_DIFFICULTY = DEFAULT_MAX_DIFFICULTY;
    }
    else if(argc == 4)
    {
        MAX_BLOCKS = atoi(argv[1]);
        N_EXPERIMENTS = atoi(argv[2]);
        MAX_DIFFICULTY = atoi(argv[3]);
    }
    else
    {
        printf("usage: ./master max_blocks experiments max_difficulty\n");
        exit(-1);
    }


#if not DUMP
    printf("----------------------------");
    printf("Press ENTER to start experiments\n");
#endif
    getchar();

#if FUNC_TESTING == 0

    struct experiment_stats stats;
    double temp = 0.0;

    if(MAX_DIFFICULTY > 32)
    {
        printf("Invalid difficulty selected\n");
        exit(-1);
    }
    //
    // To make all experiments the same
    srand(12);

    printf("[\n");
    for(uint32_t d = 4; d <= MAX_DIFFICULTY; d += 4)
    {
        uint32_t difficulty = 0xFFFFFFFF & (0xFFFFFFFF << (32 - d));
        printf("{\n");
        printf("\"DIFFICULTY\": \"%08x\",\n", difficulty);
        printf("\"BLOCK_EXPERIMENTS\": [\n");
        for(uint32_t i = 1; i < MAX_BLOCKS; ++i)
        {
            double avg = 0.0;
            double max = 0.0;
            double min = 100000000.0;
            double hash_per_sec = 0;
            for(uint32_t j = 0; j < N_EXPERIMENTS; ++j)
            {
#if ACCELERATOR
                stats = run_experiment(i, difficulty);
#else
                stats = run_experiment_cpu(i, difficulty);
#endif
                temp = stats.time_taken_ms;
                if(temp > max)max = temp;
                else if (temp < min)min=temp;
                avg += temp;
                hash_per_sec += stats.hash_per_sec;
            }
            printf("{\"Blocks\": %u, \"min_time\": %f, \"max_time\": %f, \"avg_time\": %f, \"avg_hash_per_sec\": %f}", i, min, max, avg / N_EXPERIMENTS, hash_per_sec / N_EXPERIMENTS);
            if(i != MAX_BLOCKS - 1)
                printf(",\n");
        }
        printf("]\n");
        printf("}");
        //IF WE CHANGE INCREMENT VALUE REMEMBER TO CHANGE THIS TOO
        if(d != MAX_DIFFICULTY)
            printf(",\n");
    }
    printf("]\n");


    //////////////////////////////////////////////  

#if DUMP
    fclose(stdout);
#endif
#else
    test_device();
#endif

    close(driver);
    return 0;
}

