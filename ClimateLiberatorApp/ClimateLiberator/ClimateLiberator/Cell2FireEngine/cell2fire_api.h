/*
 * cell2fire_api.h — Public C API for libcell2fire
 *
 * This header exposes the Cell2Fire simulation engine as a C-linkage
 * library so that any language (Swift, Python ctypes, C#, etc.) can
 * call it directly without spawning a subprocess.
 *
 * Typical lifecycle:
 *   1. c2f_config_create()          — allocate a config handle
 *   2. c2f_config_set_*()           — populate parameters
 *   3. c2f_sim_create(config)       — build the simulation object
 *   4. For each episode:
 *        c2f_sim_reset(sim, ep)
 *        while (!c2f_sim_is_done(sim))
 *            c2f_sim_step(sim)
 *        c2f_sim_get_results(sim, ...)
 *   5. c2f_sim_destroy(sim)
 *   6. c2f_config_destroy(config)
 */

#ifndef CELL2FIRE_API_H
#define CELL2FIRE_API_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---------- version ---------------------------------------------------- */
const char* c2f_version(void);

/* ---------- opaque handles --------------------------------------------- */
typedef struct c2f_config_t c2f_config_t;
typedef struct c2f_sim_t    c2f_sim_t;

/* ---------- error codes ------------------------------------------------ */
typedef enum {
    C2F_OK              =  0,
    C2F_ERR_NULL_ARG    = -1,
    C2F_ERR_BAD_PATH    = -2,
    C2F_ERR_BAD_PARAM   = -3,
    C2F_ERR_INIT_FAIL   = -4,
    C2F_ERR_NOT_READY   = -5
} c2f_status_t;

/* ---------- simulation result snapshot --------------------------------- */
typedef struct {
    int32_t  total_cells;
    int32_t  burnt_cells;
    int32_t  available_cells;
    int32_t  non_burnable_cells;
    int32_t  firebreak_cells;
    float    burnt_percent;
} c2f_summary_t;

/* ---------- config lifecycle ------------------------------------------- */

/** Allocate a new config with sensible defaults. */
c2f_config_t* c2f_config_create(void);

/** Free the config. Safe to call with NULL. */
void c2f_config_destroy(c2f_config_t* cfg);

/* --- required paths --- */
c2f_status_t c2f_config_set_input_folder(c2f_config_t* cfg, const char* path);
c2f_status_t c2f_config_set_output_folder(c2f_config_t* cfg, const char* path);

/* --- simulation model: "K" (Kitral), "S" (Scott & Burgan), "P" (Portugal) --- */
c2f_status_t c2f_config_set_simulator(c2f_config_t* cfg, const char* sim);

/* --- scalar parameters --- */
c2f_status_t c2f_config_set_nsims(c2f_config_t* cfg, int nsims);
c2f_status_t c2f_config_set_seed(c2f_config_t* cfg, int seed);
c2f_status_t c2f_config_set_nthreads(c2f_config_t* cfg, int nthreads);
c2f_status_t c2f_config_set_fire_period_len(c2f_config_t* cfg, float minutes);
c2f_status_t c2f_config_set_max_fire_periods(c2f_config_t* cfg, int periods);
c2f_status_t c2f_config_set_total_years(c2f_config_t* cfg, int years);

/* --- tuning factors --- */
c2f_status_t c2f_config_set_roscv(c2f_config_t* cfg, float roscv);
c2f_status_t c2f_config_set_ros_threshold(c2f_config_t* cfg, float threshold);
c2f_status_t c2f_config_set_hfi_threshold(c2f_config_t* cfg, float threshold);

/* --- output toggles --- */
c2f_status_t c2f_config_set_final_grid(c2f_config_t* cfg, int enabled);
c2f_status_t c2f_config_set_output_grids(c2f_config_t* cfg, int enabled);
c2f_status_t c2f_config_set_verbose(c2f_config_t* cfg, int enabled);
c2f_status_t c2f_config_set_out_ros(c2f_config_t* cfg, int enabled);
c2f_status_t c2f_config_set_out_intensity(c2f_config_t* cfg, int enabled);
c2f_status_t c2f_config_set_out_flame_length(c2f_config_t* cfg, int enabled);
c2f_status_t c2f_config_set_out_crown(c2f_config_t* cfg, int enabled);

/* --- optional paths --- */
c2f_status_t c2f_config_set_weather_opt(c2f_config_t* cfg, const char* opt);
c2f_status_t c2f_config_set_fuel_table(c2f_config_t* cfg, const char* path);
c2f_status_t c2f_config_set_harvest_plan(c2f_config_t* cfg, const char* path);

/* ---------- simulation lifecycle --------------------------------------- */

/**
 * Build the simulation from a completed config.
 * Returns NULL on failure (check stderr for diagnostics).
 */
c2f_sim_t* c2f_sim_create(const c2f_config_t* cfg);

/** Free the simulation. Safe to call with NULL. */
void c2f_sim_destroy(c2f_sim_t* sim);

/* ---------- run control ------------------------------------------------ */

/**
 * Run all episodes (nsims) with internal OpenMP parallelism.
 * This is the simplest "just do everything" entry point.
 * Returns C2F_OK on success.
 */
c2f_status_t c2f_sim_run_all(c2f_sim_t* sim);

/**
 * Reset the simulation for a single episode.
 * episode is 1-based (1 .. nsims).
 */
c2f_status_t c2f_sim_reset(c2f_sim_t* sim, int episode);

/**
 * Advance the simulation by one fire period.
 * Returns C2F_OK while the simulation is still running.
 * Check c2f_sim_is_done() after each call.
 */
c2f_status_t c2f_sim_step(c2f_sim_t* sim);

/** Returns non-zero if the current episode has finished. */
int c2f_sim_is_done(const c2f_sim_t* sim);

/** Finalize and write results for the current episode. */
c2f_status_t c2f_sim_finalize(c2f_sim_t* sim);

/* ---------- result accessors ------------------------------------------- */

/** Get summary statistics for the last completed episode. */
c2f_status_t c2f_sim_get_summary(const c2f_sim_t* sim, c2f_summary_t* out);

/**
 * Get the status grid (rows × cols).
 *  0 = available, 1 = burning/burnt, -1 = firebreak, -2 = non-burnable
 * Caller provides the buffer; grid_size must be >= rows*cols.
 * Returns actual cell count written via out_count.
 */
c2f_status_t c2f_sim_get_grid(const c2f_sim_t* sim,
                               int32_t* grid_buf,
                               int32_t  grid_size,
                               int32_t* out_count);

/** Get grid dimensions. */
c2f_status_t c2f_sim_get_dimensions(const c2f_sim_t* sim,
                                     int32_t* out_rows,
                                     int32_t* out_cols);

/**
 * Get rate-of-spread array for all cells.
 * Caller provides the buffer; buf_size must be >= nCells.
 */
c2f_status_t c2f_sim_get_ros(const c2f_sim_t* sim,
                              float* ros_buf,
                              int32_t buf_size);

/**
 * Get fire intensity array for all cells.
 * Caller provides the buffer; buf_size must be >= nCells.
 */
c2f_status_t c2f_sim_get_intensity(const c2f_sim_t* sim,
                                    float* intensity_buf,
                                    int32_t buf_size);

/**
 * Get flame length array for all cells.
 * Caller provides the buffer; buf_size must be >= nCells.
 */
c2f_status_t c2f_sim_get_flame_length(const c2f_sim_t* sim,
                                       float* fl_buf,
                                       int32_t buf_size);

/* ---------- progress callback ------------------------------------------ */

/**
 * Optional progress callback. Called after each fire period.
 *   episode:  1-based episode number
 *   period:   current fire period within the episode
 *   pct_done: estimated completion (0.0 – 1.0)
 *   userdata: opaque pointer passed through
 */
typedef void (*c2f_progress_fn)(int episode, int period, float pct_done, void* userdata);

/** Register a progress callback. Pass NULL to unregister. */
c2f_status_t c2f_sim_set_progress_callback(c2f_sim_t* sim,
                                            c2f_progress_fn fn,
                                            void* userdata);

#ifdef __cplusplus
}
#endif

#endif /* CELL2FIRE_API_H */
