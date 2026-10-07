/* Grain: the C interface of the Yumu launcher core (Heartwood).
 *
 * This file is written by hand and is the contract. See docs/grain-api.md.
 *
 * Every function that returns `char*` returns a UTF-8 JSON document that the
 * caller must release with grain_string_free. Responses look like
 *   {"ok": ...}                                            on success
 *   {"err": {"kind": "...", "args": {...}, "detail": "..."}} on failure
 *
 * Events arrive on arbitrary core threads as {"topic": "...", "payload": {...}}.
 * Never call back into Grain from inside the event callback.
 */
#ifndef GRAIN_H
#define GRAIN_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct GrainCore GrainCore;

typedef void (*GrainEventFn)(const char *json, void *user_data);

/* Create the core. `config_json` may be NULL or {"dataDir": "...", "concurrency": 16}.
 * Returns NULL on failure; grain_last_init_error() then describes why. */
GrainCore *grain_init(const char *config_json, GrainEventFn on_event, void *user_data);

/* Stop background work and free the core. The pointer is invalid afterwards. */
void grain_shutdown(GrainCore *core);

/* Run a synchronous method such as "instance.list". `params_json` may be NULL. */
char *grain_call(const GrainCore *core, const char *method, const char *params_json);

/* Start an asynchronous method such as "instance.launch". On success the
 * response is {"ok": {"taskId": "..."}}; progress and the outcome follow as
 * task.progress / task.completed / task.failed events. */
char *grain_start(const GrainCore *core, const char *method, const char *params_json);

/* Cancel a running task. Response: {"ok": {"cancelled": true|false}}. */
char *grain_cancel(const GrainCore *core, const char *task_id);

/* Release a string returned by this library. NULL is ignored. */
void grain_string_free(char *s);

/* Static strings owned by the library; do not free. */
const char *grain_version(void);
const char *grain_api_version(void);
const char *grain_last_init_error(void);

#ifdef __cplusplus
}
#endif

#endif
