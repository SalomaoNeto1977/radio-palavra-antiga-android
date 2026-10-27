package org.palavraantiga.radio.automotive;

/** A manual pause always cancels reconnection, including an already queued retry. */
final class RetryPolicy {
    private static final long[] DELAYS = {2000, 5000, 10000, 20000, 30000};
    private boolean requested;
    private int attempts;

    void play() { requested = true; }
    void pause() { requested = false; attempts = 0; }
    void connected() { attempts = 0; }
    boolean requested() { return requested; }
    long nextDelay() {
        if (!requested) return -1;
        return DELAYS[Math.min(attempts++, DELAYS.length - 1)];
    }
}
