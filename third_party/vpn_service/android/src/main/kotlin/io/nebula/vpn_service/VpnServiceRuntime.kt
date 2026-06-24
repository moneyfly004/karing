package io.nebula.vpn_service

internal object VpnServiceRuntime {
    private var stateEmitter: ((String, Map<String, String>) -> Unit)? = null
    private var pendingStart: ((Map<String, Any>) -> Unit)? = null

    @Volatile
    var preparedConfig: PreparedVpnConfig? = null
        private set

    @Volatile
    var currentState: String = "disconnected"
        private set

    @Synchronized
    fun setPreparedConfig(config: PreparedVpnConfig) {
        preparedConfig = config
    }

    @Synchronized
    fun setStateEmitter(emitter: ((String, Map<String, String>) -> Unit)?) {
        stateEmitter = emitter
    }

    @Synchronized
    fun updateState(state: String, params: Map<String, String> = emptyMap()) {
        currentState = state
        stateEmitter?.invoke(state, params)
    }

    @Synchronized
    fun beginStart(callback: (Map<String, Any>) -> Unit): Boolean {
        if (pendingStart != null) {
            return false
        }
        pendingStart = callback
        return true
    }

    @Synchronized
    fun completeStart(result: Map<String, Any>): Boolean {
        val callback = pendingStart ?: return false
        pendingStart = null
        callback(result)
        return true
    }

    @Synchronized
    fun clearPendingStart() {
        pendingStart = null
    }

    fun doneResult(): Map<String, Any> = mapOf("type" to "done")

    fun errorResult(message: String, isCloseError: Boolean = false): Map<String, Any> =
        mapOf(
            "type" to "error",
            "err" to mapOf(
                "message" to message,
                "is_close_error" to isCloseError,
            ),
        )

    fun timeoutResult(message: String): Map<String, Any> = mapOf("type" to "timeout", "err" to mapOf("message" to message))
}
