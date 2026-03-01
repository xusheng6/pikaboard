#ifndef PIKAFISH_BRIDGE_H
#define PIKAFISH_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

// Callback for search info updates (fires during search)
typedef void (*pikafish_info_callback)(
    int depth,
    int seldepth,
    int multipv,
    int score_cp,       // centipawn score (0 if mate)
    int score_mate,     // mate in N moves (0 if cp)
    int is_lowerbound,  // 1 if lowerbound, 0 otherwise
    int is_upperbound,  // 1 if upperbound, 0 otherwise
    unsigned long long nodes,
    unsigned long long nps,
    unsigned long long time_ms,
    int hashfull,
    const char* pv      // principal variation (space-separated UCI moves)
);

// Callback for bestmove (fires when search completes)
typedef void (*pikafish_bestmove_callback)(
    const char* bestmove,
    const char* ponder   // may be empty string
);

// Initialize engine. nnue_dir is the directory containing pikafish.nnue.
// Returns 0 on success, non-zero on failure.
int pikafish_init(const char* nnue_dir);

// Destroy engine and free resources.
void pikafish_destroy(void);

// Set callbacks (call before go).
void pikafish_set_info_callback(pikafish_info_callback cb);
void pikafish_set_bestmove_callback(pikafish_bestmove_callback cb);

// Set position from FEN. moves is space-separated UCI moves or NULL.
void pikafish_set_position(const char* fen, const char* moves);

// Start analysis with fixed depth (non-blocking).
void pikafish_go_depth(int depth);

// Start infinite analysis (non-blocking).
void pikafish_go_infinite(void);

// Stop current search.
void pikafish_stop(void);

// Wait for search to finish (blocking).
void pikafish_wait(void);

// Set engine option (e.g., "Threads", "1").
void pikafish_set_option(const char* name, const char* value);

#ifdef __cplusplus
}
#endif

#endif // PIKAFISH_BRIDGE_H
