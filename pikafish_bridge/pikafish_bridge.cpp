#include "pikafish_bridge.h"

#include <cstring>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

#include "bitboard.h"
#include "engine.h"
#include "misc.h"
#include "position.h"
#include "score.h"
#include "search.h"
#include "tune.h"
#include "types.h"
#include "ucioption.h"

using namespace Stockfish;

static std::unique_ptr<Engine> g_engine;
static std::mutex              g_callback_mutex;
static pikafish_info_callback     g_info_cb     = nullptr;
static pikafish_bestmove_callback g_bestmove_cb = nullptr;
static bool g_initialized = false;

// Persistent buffers for callback string data.
// NativeCallable.listener in Dart is asynchronous, so local C++ strings
// would be destroyed before Dart reads them. These buffers persist until
// overwritten by the next callback invocation.
static char g_pv_buf[8192];
static char g_bestmove_buf[16];
static char g_ponder_buf[16];

static void on_update_full(const Search::InfoFull& info) {
    pikafish_info_callback cb;
    {
        std::lock_guard<std::mutex> lock(g_callback_mutex);
        cb = g_info_cb;
    }
    if (!cb)
        return;

    int score_cp   = 0;
    int score_mate = 0;

    info.score.visit([&](auto&& val) {
        using T = std::decay_t<decltype(val)>;
        if constexpr (std::is_same_v<T, Score::InternalUnits>) {
            score_cp = val.value;
        } else if constexpr (std::is_same_v<T, Score::Mate>) {
            score_mate = (val.plies > 0 ? (val.plies + 1) : val.plies) / 2;
        }
    });

    int is_lower = 0, is_upper = 0;
    if (!info.bound.empty()) {
        std::string bound_str(info.bound);
        if (bound_str == "lowerbound")
            is_lower = 1;
        else if (bound_str == "upperbound")
            is_upper = 1;
    }

    // Copy PV to persistent buffer
    size_t pv_len = info.pv.size();
    if (pv_len >= sizeof(g_pv_buf))
        pv_len = sizeof(g_pv_buf) - 1;
    memcpy(g_pv_buf, info.pv.data(), pv_len);
    g_pv_buf[pv_len] = '\0';

    cb(info.depth,
       info.selDepth,
       static_cast<int>(info.multiPV),
       score_cp,
       score_mate,
       is_lower,
       is_upper,
       static_cast<unsigned long long>(info.nodes),
       static_cast<unsigned long long>(info.nps),
       static_cast<unsigned long long>(info.timeMs),
       info.hashfull,
       g_pv_buf);
}

static void on_bestmove(std::string_view bestmove, std::string_view ponder) {
    pikafish_bestmove_callback cb;
    {
        std::lock_guard<std::mutex> lock(g_callback_mutex);
        cb = g_bestmove_cb;
    }
    if (!cb)
        return;

    // Copy to persistent buffers
    size_t bm_len = bestmove.size();
    if (bm_len >= sizeof(g_bestmove_buf))
        bm_len = sizeof(g_bestmove_buf) - 1;
    memcpy(g_bestmove_buf, bestmove.data(), bm_len);
    g_bestmove_buf[bm_len] = '\0';

    size_t pd_len = ponder.size();
    if (pd_len >= sizeof(g_ponder_buf))
        pd_len = sizeof(g_ponder_buf) - 1;
    memcpy(g_ponder_buf, ponder.data(), pd_len);
    g_ponder_buf[pd_len] = '\0';

    cb(g_bestmove_buf, g_ponder_buf);
}

static void on_update_no_moves(const Search::InfoShort& info) {
    // Minimal info when no legal moves - treat as info callback with limited data
    pikafish_info_callback cb;
    {
        std::lock_guard<std::mutex> lock(g_callback_mutex);
        cb = g_info_cb;
    }
    if (!cb)
        return;

    int score_cp   = 0;
    int score_mate = 0;

    info.score.visit([&](auto&& val) {
        using T = std::decay_t<decltype(val)>;
        if constexpr (std::is_same_v<T, Score::InternalUnits>) {
            score_cp = val.value;
        } else if constexpr (std::is_same_v<T, Score::Mate>) {
            score_mate = (val.plies > 0 ? (val.plies + 1) : val.plies) / 2;
        }
    });

    cb(info.depth, 0, 1, score_cp, score_mate, 0, 0, 0, 0, 0, 0, "");
}

extern "C" {

int pikafish_init(const char* nnue_dir) {
    if (g_initialized)
        return 0;

    fprintf(stderr, "[pikafish] init: starting, nnue_dir=%s\n", nnue_dir ? nnue_dir : "(null)");
    fflush(stderr);

    fprintf(stderr, "[pikafish] init: Bitboards::init()...\n"); fflush(stderr);
    Bitboards::init();

    fprintf(stderr, "[pikafish] init: Position::init()...\n"); fflush(stderr);
    Position::init();

    std::string path(nnue_dir ? nnue_dir : "");
    fprintf(stderr, "[pikafish] init: creating Engine with path=%s\n", path.c_str()); fflush(stderr);
    g_engine = std::make_unique<Engine>(path);

    fprintf(stderr, "[pikafish] init: Engine created, running Tune::init\n"); fflush(stderr);
    Tune::init(g_engine->get_options());

    fprintf(stderr, "[pikafish] init: registering callbacks\n"); fflush(stderr);
    // Register callbacks
    g_engine->set_on_update_full([](const auto& i) { on_update_full(i); });
    g_engine->set_on_bestmove([](const auto& bm, const auto& p) { on_bestmove(bm, p); });
    g_engine->set_on_update_no_moves([](const auto& i) { on_update_no_moves(i); });
    g_engine->set_on_iter([](const auto&) {}); // ignore iteration info
    g_engine->set_on_verify_networks([](const auto&) {}); // ignore network verify messages

    g_initialized = true;
    fprintf(stderr, "[pikafish] init: done!\n"); fflush(stderr);
    return 0;
}

void pikafish_destroy(void) {
    if (!g_initialized)
        return;

    g_engine->stop();
    g_engine->wait_for_search_finished();
    g_engine.reset();
    g_initialized = false;
}

void pikafish_set_info_callback(pikafish_info_callback cb) {
    std::lock_guard<std::mutex> lock(g_callback_mutex);
    g_info_cb = cb;
}

void pikafish_set_bestmove_callback(pikafish_bestmove_callback cb) {
    std::lock_guard<std::mutex> lock(g_callback_mutex);
    g_bestmove_cb = cb;
}

void pikafish_set_position(const char* fen, const char* moves) {
    if (!g_initialized || !g_engine)
        return;

    std::string fen_str(fen ? fen : "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w");
    std::vector<std::string> move_list;

    if (moves && strlen(moves) > 0) {
        std::istringstream iss(moves);
        std::string move;
        while (iss >> move)
            move_list.push_back(move);
    }

    g_engine->set_position(fen_str, move_list);
}

void pikafish_go_depth(int depth) {
    if (!g_initialized || !g_engine)
        return;

    Search::LimitsType limits;
    limits.startTime = now();
    limits.depth     = depth;
    g_engine->go(limits);
}

void pikafish_go_infinite(void) {
    if (!g_initialized || !g_engine)
        return;

    Search::LimitsType limits;
    limits.startTime = now();
    limits.infinite  = 1;
    g_engine->go(limits);
}

void pikafish_stop(void) {
    if (!g_initialized || !g_engine)
        return;
    g_engine->stop();
}

void pikafish_wait(void) {
    if (!g_initialized || !g_engine)
        return;
    g_engine->wait_for_search_finished();
}

void pikafish_set_option(const char* name, const char* value) {
    if (!g_initialized || !g_engine)
        return;

    std::string cmd = "name " + std::string(name) + " value " + std::string(value);
    std::istringstream is(cmd);
    g_engine->get_options().setoption(is);
}

} // extern "C"
