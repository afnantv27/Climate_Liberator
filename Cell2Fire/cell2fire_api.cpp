/*
 * cell2fire_api.cpp — Implementation of the C API for libcell2fire
 *
 * Wraps the existing Cell2Fire C++ engine behind opaque handles
 * so callers never touch C++ types directly.
 */

#include "cell2fire_api.h"
#include "Cell2Fire.h"
#include "DataGenerator.h"
#include "FuelModelFBP.h"
#include "FuelModelKitral.h"
#include "FuelModelPortugal.h"
#include "FuelModelSpain.h"
#include "ReadArgs.h"

#include <boost/random.hpp>
#include <cmath>
#include <cstring>
#include <iostream>
#include <omp.h>
#include <string>
#include <vector>

/* forward-declare globals that Cell2Fire.cpp normally defines */
extern inputs* df;
extern inputs* df_ptr;
extern std::unordered_map<int, std::vector<float>> BBOFactors;
extern std::unordered_map<int, std::vector<int>> HarvestedCells;
extern std::vector<int> NFTypesCells;
extern std::unordered_map<int, int> IgnitionHistory;
extern std::unordered_map<int, std::string> WeatherHistory;

/* ------------------------------------------------------------------ */
/*  Opaque handle definitions                                         */
/* ------------------------------------------------------------------ */

struct c2f_config_t {
    arguments args;
    bool verbose;
    c2f_config_t() : verbose(false) {
        /* Mirror the defaults from parseArgs — keep in sync */
        args.InFolder        = "";
        args.OutFolder       = "";
        args.Simulator       = "K";
        args.WeatherOpt      = "rows";
        args.TotalSims       = 1;
        args.seed            = 123;
        args.nthreads        = 1;
        args.FirePeriodLen   = 1.0f;
        args.MaxFirePeriods  = 100;
        args.TotalYears      = 1;
        args.NWeatherFiles   = 1;
        args.MinutesPerWP    = 60;
        args.ROSCV           = 0.0f;
        args.ROSThreshold    = 1e-4f;
        args.ContactROSThreshold = 1e-4f;
        args.CROSThreshold   = 0.4f;
        args.HFIThreshold    = 10000.0f;
        args.HFactor         = 1.0f;
        args.FFactor         = 1.0f;
        args.BFactor         = 1.0f;
        args.EFactor         = 1.0f;
        args.CBDFactor       = 1.0f;
        args.CCFFactor       = 1.0f;
        args.ROS10Factor     = 1.0f;
        args.CROSActThreshold = 0.0f;
        args.FMC             = 85;
        args.scenario        = 1;
        args.IgnitionRadius  = 0;
        args.Ignitions       = false;
        args.ForceCenterIgnition = false;
        args.OutputGrids     = false;
        args.FinalGrid       = true;
        args.OutMessages     = false;
        args.OutFl           = false;
        args.OutIntensity    = false;
        args.OutRos          = false;
        args.OutCrown        = false;
        args.OutCrownConsumption = false;
        args.OutSurfConsumption  = false;
        args.Trajectories    = false;
        args.NoOutput        = false;
        args.verbose         = false;
        args.IgnitionsLog    = false;
        args.PromTuned       = false;
        args.Stats           = false;
        args.BBOTuning       = false;
        args.AllowCROS       = false;
        args.FuelTablePath   = "";
        args.HarvestPlan     = "";
    }
};

struct c2f_sim_t {
    arguments                args;
    Cell2Fire*               forest;        /* primary instance */
    std::vector<Cell2Fire>*  thread_copies; /* per-thread copies */
    boost::random::mt19937   generator;
    int                      current_episode;
    c2f_progress_fn          progress_fn;
    void*                    progress_userdata;

    c2f_sim_t()
        : forest(nullptr)
        , thread_copies(nullptr)
        , current_episode(0)
        , progress_fn(nullptr)
        , progress_userdata(nullptr)
    {}

    ~c2f_sim_t() {
        delete thread_copies;
        delete forest;
    }
};

/* ------------------------------------------------------------------ */
/*  Version                                                           */
/* ------------------------------------------------------------------ */

extern std::string C2FW_VERSION;

const char*
c2f_version(void)
{
    return C2FW_VERSION.c_str();
}

/* ------------------------------------------------------------------ */
/*  Config lifecycle                                                  */
/* ------------------------------------------------------------------ */

c2f_config_t*
c2f_config_create(void)
{
    return new (std::nothrow) c2f_config_t();
}

void
c2f_config_destroy(c2f_config_t* cfg)
{
    delete cfg;
}

/* helper: ensure trailing path separator */
static std::string
ensure_trailing_sep(const std::string& path)
{
    if (path.empty()) return path;
    char last = path.back();
    if (last != '/' && last != '\\')
        return path + "/";
    return path;
}

/* --- required paths --- */

c2f_status_t
c2f_config_set_input_folder(c2f_config_t* cfg, const char* path)
{
    if (!cfg || !path) return C2F_ERR_NULL_ARG;
    cfg->args.InFolder = ensure_trailing_sep(path);
    return C2F_OK;
}

c2f_status_t
c2f_config_set_output_folder(c2f_config_t* cfg, const char* path)
{
    if (!cfg || !path) return C2F_ERR_NULL_ARG;
    cfg->args.OutFolder = ensure_trailing_sep(path);
    return C2F_OK;
}

c2f_status_t
c2f_config_set_simulator(c2f_config_t* cfg, const char* sim)
{
    if (!cfg || !sim) return C2F_ERR_NULL_ARG;
    std::string s(sim);
    if (s != "K" && s != "S" && s != "P") return C2F_ERR_BAD_PARAM;
    cfg->args.Simulator = s;
    return C2F_OK;
}

/* --- scalar parameters --- */

c2f_status_t c2f_config_set_nsims(c2f_config_t* cfg, int n)
{
    if (!cfg) return C2F_ERR_NULL_ARG;
    if (n < 1) return C2F_ERR_BAD_PARAM;
    cfg->args.TotalSims = n;
    return C2F_OK;
}

c2f_status_t c2f_config_set_seed(c2f_config_t* cfg, int seed)
{
    if (!cfg) return C2F_ERR_NULL_ARG;
    cfg->args.seed = seed;
    return C2F_OK;
}

c2f_status_t c2f_config_set_nthreads(c2f_config_t* cfg, int n)
{
    if (!cfg) return C2F_ERR_NULL_ARG;
    if (n < 1) return C2F_ERR_BAD_PARAM;
    cfg->args.nthreads = n;
    return C2F_OK;
}

c2f_status_t c2f_config_set_fire_period_len(c2f_config_t* cfg, float m)
{
    if (!cfg) return C2F_ERR_NULL_ARG;
    if (m <= 0.0f) return C2F_ERR_BAD_PARAM;
    cfg->args.FirePeriodLen = m;
    return C2F_OK;
}

c2f_status_t c2f_config_set_max_fire_periods(c2f_config_t* cfg, int p)
{
    if (!cfg) return C2F_ERR_NULL_ARG;
    if (p < 1) return C2F_ERR_BAD_PARAM;
    cfg->args.MaxFirePeriods = p;
    return C2F_OK;
}

c2f_status_t c2f_config_set_total_years(c2f_config_t* cfg, int y)
{
    if (!cfg) return C2F_ERR_NULL_ARG;
    if (y < 1) return C2F_ERR_BAD_PARAM;
    cfg->args.TotalYears = y;
    return C2F_OK;
}

/* --- tuning factors --- */

c2f_status_t c2f_config_set_roscv(c2f_config_t* cfg, float v)
{
    if (!cfg) return C2F_ERR_NULL_ARG;
    cfg->args.ROSCV = v;
    return C2F_OK;
}

c2f_status_t c2f_config_set_ros_threshold(c2f_config_t* cfg, float v)
{
    if (!cfg) return C2F_ERR_NULL_ARG;
    cfg->args.ROSThreshold = v;
    return C2F_OK;
}

c2f_status_t c2f_config_set_hfi_threshold(c2f_config_t* cfg, float v)
{
    if (!cfg) return C2F_ERR_NULL_ARG;
    cfg->args.HFIThreshold = v;
    return C2F_OK;
}

/* --- output toggles --- */

c2f_status_t c2f_config_set_final_grid(c2f_config_t* cfg, int e)
{
    if (!cfg) return C2F_ERR_NULL_ARG;
    cfg->args.FinalGrid = (e != 0);
    return C2F_OK;
}

c2f_status_t c2f_config_set_output_grids(c2f_config_t* cfg, int e)
{
    if (!cfg) return C2F_ERR_NULL_ARG;
    cfg->args.OutputGrids = (e != 0);
    return C2F_OK;
}

c2f_status_t c2f_config_set_verbose(c2f_config_t* cfg, int e)
{
    if (!cfg) return C2F_ERR_NULL_ARG;
    cfg->args.verbose = (e != 0);
    cfg->verbose = (e != 0);
    return C2F_OK;
}

c2f_status_t c2f_config_set_out_ros(c2f_config_t* cfg, int e)
{
    if (!cfg) return C2F_ERR_NULL_ARG;
    cfg->args.OutRos = (e != 0);
    return C2F_OK;
}

c2f_status_t c2f_config_set_out_intensity(c2f_config_t* cfg, int e)
{
    if (!cfg) return C2F_ERR_NULL_ARG;
    cfg->args.OutIntensity = (e != 0);
    return C2F_OK;
}

c2f_status_t c2f_config_set_out_flame_length(c2f_config_t* cfg, int e)
{
    if (!cfg) return C2F_ERR_NULL_ARG;
    cfg->args.OutFl = (e != 0);
    return C2F_OK;
}

c2f_status_t c2f_config_set_out_crown(c2f_config_t* cfg, int e)
{
    if (!cfg) return C2F_ERR_NULL_ARG;
    cfg->args.OutCrown = (e != 0);
    return C2F_OK;
}

/* --- optional paths --- */

c2f_status_t c2f_config_set_weather_opt(c2f_config_t* cfg, const char* opt)
{
    if (!cfg || !opt) return C2F_ERR_NULL_ARG;
    cfg->args.WeatherOpt = opt;
    return C2F_OK;
}

c2f_status_t c2f_config_set_fuel_table(c2f_config_t* cfg, const char* path)
{
    if (!cfg || !path) return C2F_ERR_NULL_ARG;
    cfg->args.FuelTablePath = path;
    return C2F_OK;
}

c2f_status_t c2f_config_set_harvest_plan(c2f_config_t* cfg, const char* path)
{
    if (!cfg || !path) return C2F_ERR_NULL_ARG;
    cfg->args.HarvestPlan = path;
    return C2F_OK;
}

/* ------------------------------------------------------------------ */
/*  Simulation lifecycle                                              */
/* ------------------------------------------------------------------ */

c2f_sim_t*
c2f_sim_create(const c2f_config_t* cfg)
{
    if (!cfg) return nullptr;
    if (cfg->args.InFolder.empty() || cfg->args.OutFolder.empty()) {
        std::cerr << "c2f_sim_create: input/output folders are required\n";
        return nullptr;
    }

    c2f_sim_t* sim = new (std::nothrow) c2f_sim_t();
    if (!sim) return nullptr;

    sim->args = cfg->args;

    /* count weather files like parseArgs does */
    sim->args.NWeatherFiles = countWeathers(sim->args.InFolder);
    if (sim->args.NWeatherFiles < 1)
        sim->args.NWeatherFiles = 1;

    try {
        /* generate data files (same as main) */
        GenDataFile(sim->args.InFolder, sim->args.Simulator);

        /* initialize fuel model coefficients */
        if (sim->args.Simulator == "K") {
            setup_const();
        } else if (sim->args.Simulator == "S") {
            initialize_coeff(sim->args.scenario);
        } else if (sim->args.Simulator == "P") {
            initialize_coeff_p(sim->args.scenario);
        }

        /* build primary Forest object */
        sim->forest = new Cell2Fire(sim->args);

        /* create per-thread copies */
        int nt = sim->args.nthreads;
        sim->thread_copies = new std::vector<Cell2Fire>(nt, *(sim->forest));

    } catch (const std::exception& e) {
        std::cerr << "c2f_sim_create failed: " << e.what() << "\n";
        delete sim;
        return nullptr;
    } catch (...) {
        std::cerr << "c2f_sim_create failed: unknown error\n";
        delete sim;
        return nullptr;
    }

    return sim;
}

void
c2f_sim_destroy(c2f_sim_t* sim)
{
    if (sim) {
        delete[] df;
        df = nullptr;
    }
    delete sim;
}

/* ------------------------------------------------------------------ */
/*  Run all — mirrors the original main() OpenMP loop                 */
/* ------------------------------------------------------------------ */

c2f_status_t
c2f_sim_run_all(c2f_sim_t* sim)
{
    if (!sim || !sim->forest) return C2F_ERR_NULL_ARG;

    const arguments& args = sim->args;
    int num_threads = args.nthreads;
    auto& Forests = *(sim->thread_copies);

#pragma omp parallel num_threads(num_threads)
    {
        int TID = omp_get_thread_num();
        Cell2Fire Forest = Forests[TID];

        int rnumber;
        double rnumber2;

#pragma omp for
        for (int ep = 1; ep <= args.TotalSims; ep++)
        {
            boost::random::mt19937 generator(args.seed * ep);
            boost::random::uniform_int_distribution<int> udist(1, args.NWeatherFiles);
            boost::random::normal_distribution<> ndist(0.0, 1.0);

            rnumber  = udist(generator);
            rnumber2 = ndist(generator);

            Forest.reset(rnumber, rnumber2, ep);

            for (int tstep = 0;
                 tstep <= Forest.totalFirePeriods * Forest.args.TotalYears;
                 tstep++)
            {
                Forest.Step(generator, ep);

                /* call progress callback if registered */
                if (sim->progress_fn) {
                    float pct = static_cast<float>(tstep) /
                                static_cast<float>(Forest.totalFirePeriods * Forest.args.TotalYears);
                    sim->progress_fn(ep, tstep, pct, sim->progress_userdata);
                }

                if (Forest.done)
                    break;
            }

            if (!Forest.done) {
                Forest.Results();
                Forest.sim += 1;
                Forest.done = true;
            }
        }
    }

    return C2F_OK;
}

/* ------------------------------------------------------------------ */
/*  Step-by-step control — single-threaded fine-grained API           */
/* ------------------------------------------------------------------ */

c2f_status_t
c2f_sim_reset(c2f_sim_t* sim, int episode)
{
    if (!sim || !sim->forest) return C2F_ERR_NULL_ARG;
    if (episode < 1) return C2F_ERR_BAD_PARAM;

    sim->current_episode = episode;
    sim->generator = boost::random::mt19937(sim->args.seed * episode);

    boost::random::uniform_int_distribution<int> udist(1, sim->args.NWeatherFiles);
    boost::random::normal_distribution<> ndist(0.0, 1.0);

    int rnumber     = udist(sim->generator);
    double rnumber2 = ndist(sim->generator);

    sim->forest->reset(rnumber, rnumber2, episode);
    return C2F_OK;
}

c2f_status_t
c2f_sim_step(c2f_sim_t* sim)
{
    if (!sim || !sim->forest) return C2F_ERR_NULL_ARG;
    if (sim->forest->done) return C2F_ERR_NOT_READY;

    sim->forest->Step(sim->generator, sim->current_episode);
    return C2F_OK;
}

int
c2f_sim_is_done(const c2f_sim_t* sim)
{
    if (!sim || !sim->forest) return 1;
    return sim->forest->done ? 1 : 0;
}

c2f_status_t
c2f_sim_finalize(c2f_sim_t* sim)
{
    if (!sim || !sim->forest) return C2F_ERR_NULL_ARG;
    if (!sim->forest->done) {
        sim->forest->Results();
        sim->forest->sim += 1;
        sim->forest->done = true;
    }
    return C2F_OK;
}

/* ------------------------------------------------------------------ */
/*  Result accessors                                                  */
/* ------------------------------------------------------------------ */

c2f_status_t
c2f_sim_get_summary(const c2f_sim_t* sim, c2f_summary_t* out)
{
    if (!sim || !sim->forest || !out) return C2F_ERR_NULL_ARG;

    const Cell2Fire& f = *(sim->forest);
    int32_t total    = static_cast<int32_t>(f.nCells);
    int32_t burnt    = static_cast<int32_t>(f.burntCells.size());
    int32_t nb       = static_cast<int32_t>(f.nonBurnableCells.size());
    int32_t fb       = static_cast<int32_t>(f.harvestCells.size());
    int32_t avail    = total - burnt - nb - fb;

    out->total_cells        = total;
    out->burnt_cells        = burnt;
    out->available_cells    = avail;
    out->non_burnable_cells = nb;
    out->firebreak_cells    = fb;
    out->burnt_percent      = (total > 0) ? (100.0f * burnt / total) : 0.0f;

    return C2F_OK;
}

c2f_status_t
c2f_sim_get_dimensions(const c2f_sim_t* sim, int32_t* out_rows, int32_t* out_cols)
{
    if (!sim || !sim->forest) return C2F_ERR_NULL_ARG;
    if (out_rows) *out_rows = sim->forest->rows;
    if (out_cols) *out_cols = sim->forest->cols;
    return C2F_OK;
}

c2f_status_t
c2f_sim_get_grid(const c2f_sim_t* sim,
                  int32_t* grid_buf,
                  int32_t  grid_size,
                  int32_t* out_count)
{
    if (!sim || !sim->forest || !grid_buf) return C2F_ERR_NULL_ARG;

    const Cell2Fire& f = *(sim->forest);
    int32_t n = static_cast<int32_t>(f.nCells);
    if (grid_size < n) return C2F_ERR_BAD_PARAM;

    for (int32_t i = 0; i < n; i++) {
        int st = f.statusCells[i];
        if (st == 0)      grid_buf[i] =  0;  /* available */
        else if (st == 2)  grid_buf[i] =  1;  /* burnt */
        else if (st == 3)  grid_buf[i] = -1;  /* firebreak */
        else if (st == 4)  grid_buf[i] = -2;  /* non-burnable */
        else               grid_buf[i] =  1;  /* burning or other → treat as burnt */
    }

    if (out_count) *out_count = n;
    return C2F_OK;
}

c2f_status_t
c2f_sim_get_ros(const c2f_sim_t* sim, float* buf, int32_t buf_size)
{
    if (!sim || !sim->forest || !buf) return C2F_ERR_NULL_ARG;
    const auto& v = sim->forest->RateOfSpreads;
    int32_t n = static_cast<int32_t>(v.size());
    if (buf_size < n) return C2F_ERR_BAD_PARAM;
    std::memcpy(buf, v.data(), n * sizeof(float));
    return C2F_OK;
}

c2f_status_t
c2f_sim_get_intensity(const c2f_sim_t* sim, float* buf, int32_t buf_size)
{
    if (!sim || !sim->forest || !buf) return C2F_ERR_NULL_ARG;
    const auto& v = sim->forest->surfaceIntensities;
    int32_t n = static_cast<int32_t>(v.size());
    if (buf_size < n) return C2F_ERR_BAD_PARAM;
    std::memcpy(buf, v.data(), n * sizeof(float));
    return C2F_OK;
}

c2f_status_t
c2f_sim_get_flame_length(const c2f_sim_t* sim, float* buf, int32_t buf_size)
{
    if (!sim || !sim->forest || !buf) return C2F_ERR_NULL_ARG;
    const auto& v = sim->forest->surfaceFlameLengths;
    int32_t n = static_cast<int32_t>(v.size());
    if (buf_size < n) return C2F_ERR_BAD_PARAM;
    std::memcpy(buf, v.data(), n * sizeof(float));
    return C2F_OK;
}

/* ------------------------------------------------------------------ */
/*  Progress callback                                                 */
/* ------------------------------------------------------------------ */

c2f_status_t
c2f_sim_set_progress_callback(c2f_sim_t* sim, c2f_progress_fn fn, void* userdata)
{
    if (!sim) return C2F_ERR_NULL_ARG;
    sim->progress_fn       = fn;
    sim->progress_userdata = userdata;
    return C2F_OK;
}
