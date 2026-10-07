// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

enum Faction {
    NONE,
    HOME,
    AWAY
}

enum MatchStatus {
    OPEN,
    LOCKED,
    PENDING_RESOLUTION,
    SETTLED,
    REFUNDED,
    DISPUTED
}

enum Outcome {
    NONE,
    HOME_WIN,
    AWAY_WIN,
    DRAW,
    CANCELLED
}
