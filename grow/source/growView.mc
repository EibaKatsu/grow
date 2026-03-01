import Toybox.Activity;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

class growView extends WatchUi.SimpleDataField {
    private const HR_MAX_DEFAULT = 190.0f;
    private const SLOPE_UP_THRESHOLD = 0.03f;
    private const SLOPE_DOWN_THRESHOLD = -0.03f;
    private const MIN_DISTANCE_DELTA_METERS = 20.0f;
    private const DEBUG_SLOPE_LOG = false;
    private const DIST_EVENT_TOLERANCE_KM = 0.02f;
    private const DIST_SPECIAL_MARKERS = [5.0f, 10.0f, 15.0f, 20.0f, 21.1f, 25.0f, 30.0f, 35.0f, 40.0f, 42.2f];
    private const MIN_MESSAGE_UPDATE_MS = 5000;
    private const RECENT_MESSAGE_WINDOW = 5;
    private const CATEGORY_PICK_ATTEMPTS = 6;

    private var _lastAltitude as Float?;
    private var _lastDistance as Float?;
    private var _slopeState as String;
    private var _lastKmEvent as Float;
    private var _lastSeenDistanceKm as Float?;
    private var _displayMessage as String;
    private var _lastMessageUpdateMs as Number?;
    private var _recentMessages;

    function initialize() {
        SimpleDataField.initialize();
        label = "HR Zone";
        _lastAltitude = null;
        _lastDistance = null;
        _slopeState = "FL";
        _lastKmEvent = 0.0f;
        _lastSeenDistanceKm = null;
        _displayMessage = "Grow";
        _lastMessageUpdateMs = null;
        _recentMessages = [];
    }

    private function zoneFromHeartRate(heartRate as Number?) as String {
        if (heartRate == null || heartRate <= 0) {
            return "Z-";
        }

        var hrp = heartRate.toFloat() / HR_MAX_DEFAULT;
        if (hrp < 0.60f) {
            return "Z1";
        } else if (hrp < 0.70f) {
            return "Z2";
        } else if (hrp < 0.80f) {
            return "Z3";
        } else if (hrp < 0.90f) {
            return "Z4";
        }

        return "Z5";
    }

    private function updateSlopeState(altitude as Float?, elapsedDistance as Float?) as String {
        if (altitude == null || elapsedDistance == null) {
            if (DEBUG_SLOPE_LOG) {
                System.println(
                    "[grow][slope] skip: altitudeNull=" + (altitude == null)
                    + " distanceNull=" + (elapsedDistance == null)
                );
            }
            return _slopeState;
        }

        if (_lastAltitude == null || _lastDistance == null) {
            if (DEBUG_SLOPE_LOG) {
                System.println("[grow][slope] anchor init alt=" + altitude + " dist=" + elapsedDistance);
            }
            _lastAltitude = altitude;
            _lastDistance = elapsedDistance;
            return _slopeState;
        }

        var deltaDistance = elapsedDistance - _lastDistance;
        if (DEBUG_SLOPE_LOG) {
            System.println(
                "[grow][slope] deltaDistance=" + deltaDistance
                + " currentDist=" + elapsedDistance
                + " anchorDist=" + _lastDistance
            );
        }
        // Activity restart or seek: reset anchor.
        if (deltaDistance <= 0.0f) {
            if (DEBUG_SLOPE_LOG) {
                System.println("[grow][slope] reset anchor: deltaDistance<=0");
            }
            _lastAltitude = altitude;
            _lastDistance = elapsedDistance;
            _slopeState = "FL";
            return _slopeState;
        }

        // Keep accumulating against the same anchor until enough distance is covered.
        if (deltaDistance < MIN_DISTANCE_DELTA_METERS) {
            if (DEBUG_SLOPE_LOG) {
                System.println("[grow][slope] hold: deltaDistance<" + MIN_DISTANCE_DELTA_METERS);
            }
            return _slopeState;
        }

        var deltaAltitude = altitude - _lastAltitude;
        var grade = deltaAltitude / deltaDistance;
        if (DEBUG_SLOPE_LOG) {
            System.println("[grow][slope] deltaAltitude=" + deltaAltitude + " grade=" + grade);
        }
        if (grade >= SLOPE_UP_THRESHOLD) {
            _slopeState = "UP";
        } else if (grade <= SLOPE_DOWN_THRESHOLD) {
            _slopeState = "DN";
        } else {
            _slopeState = "FL";
        }
        if (DEBUG_SLOPE_LOG) {
            System.println("[grow][slope] state=" + _slopeState);
        }

        _lastAltitude = altitude;
        _lastDistance = elapsedDistance;
        return _slopeState;
    }

    private function buildStateKey(slope as String, zone as String) as String {
        return slope + "_" + zone;
    }

    private function stateKeyCode(stateKey as String) as Number {
        switch (stateKey) {
            case "UP_Z1": return 1;
            case "UP_Z2": return 2;
            case "UP_Z3": return 3;
            case "UP_Z4": return 4;
            case "UP_Z5": return 5;
            case "FL_Z1": return 6;
            case "FL_Z2": return 7;
            case "FL_Z3": return 8;
            case "FL_Z4": return 9;
            case "FL_Z5": return 10;
            case "DN_Z1": return 11;
            case "DN_Z2": return 12;
            case "DN_Z3": return 13;
            case "DN_Z4": return 14;
            case "DN_Z5": return 15;
        }

        return 0;
    }

    private function pickTrainingCategory(info as Activity.Info, stateKey as String) as String {
        // Step 4 ratio target:
        // FUNNY 25 / SALT 20 / ALCOHOL 20 / TOXIC 10 / FIXED 15 / PRAISE 10
        var bucketSource = stateKeyCode(stateKey) * 7;

        if (info.timerTime != null) {
            // Change selection roughly every 10s to keep output readable.
            bucketSource += (info.timerTime / 10000).toNumber();
        }
        if (info.currentHeartRate != null) {
            bucketSource += info.currentHeartRate;
        }
        if (info.elapsedDistance != null) {
            bucketSource += (info.elapsedDistance / 25.0f).toNumber();
        }

        var bucket = bucketSource % 100;
        if (bucket < 25) {
            return "FUNNY";
        } else if (bucket < 45) {
            return "SALT";
        } else if (bucket < 65) {
            return "ALCOHOL";
        } else if (bucket < 75) {
            return "TOXIC";
        } else if (bucket < 90) {
            return "FIXED";
        }

        return "PRAISE";
    }

    private function pickCategoryMessage(category as String, stateKey as String, variant as Number) as String {
        var idx = variant % 3;
        switch (category) {
            case "FIXED":
                return pickFixedMessage(stateKey);
            case "FUNNY":
                if (idx == 0) {
                    return "Keep it light";
                } else if (idx == 1) {
                    return "Relax your face";
                }
                return "Smile and flow";
            case "SALT":
                if (idx == 0) {
                    return "Stay sharp";
                } else if (idx == 1) {
                    return "Check your pace";
                }
                return "Lock the rhythm";
            case "ALCOHOL":
                if (idx == 0) {
                    return "Water first";
                } else if (idx == 1) {
                    return "No bar legs";
                }
                return "Sip and move";
            case "TOXIC":
                if (idx == 0) {
                    return "No excuses";
                } else if (idx == 1) {
                    return "You can do more";
                }
                return "Stay in it";
            case "PRAISE":
                if (idx == 0) {
                    return "Strong work";
                } else if (idx == 1) {
                    return "Great control";
                }
                return "Nice discipline";
        }

        return pickFixedMessage(stateKey);
    }

    private function buildDistanceEventMessage(markerKm as Float) as String {
        return "DIST " + markerKm.toString() + "km";
    }

    private function detectDistanceEvent(elapsedDistance as Float?) as String or Null {
        if (elapsedDistance == null) {
            return null;
        }

        var distanceKm = elapsedDistance / 1000.0f;
        if (_lastSeenDistanceKm != null && (distanceKm + DIST_EVENT_TOLERANCE_KM) < _lastSeenDistanceKm) {
            // Activity restarted or playback seeked back.
            _lastKmEvent = 0.0f;
        }
        _lastSeenDistanceKm = distanceKm;

        var limit = distanceKm + DIST_EVENT_TOLERANCE_KM;
        var crossedMarker = _lastKmEvent;

        var maxWholeKm = limit.toNumber();
        var km = 1;
        while (km <= maxWholeKm) {
            var marker = km.toFloat();
            if (marker > _lastKmEvent && marker <= limit && marker > crossedMarker) {
                crossedMarker = marker;
            }
            km += 1;
        }

        for (var i = 0; i < DIST_SPECIAL_MARKERS.size(); i += 1) {
            var specialMarker = DIST_SPECIAL_MARKERS[i];
            if (specialMarker > _lastKmEvent && specialMarker <= limit && specialMarker > crossedMarker) {
                crossedMarker = specialMarker;
            }
        }

        if (crossedMarker > _lastKmEvent) {
            _lastKmEvent = crossedMarker;
            return buildDistanceEventMessage(crossedMarker);
        }

        return null;
    }

    private function buildMessagePickSeed(info as Activity.Info, stateKey as String) as Number {
        var seed = stateKeyCode(stateKey) * 13;
        if (info.timerTime != null) {
            seed += (info.timerTime / 1000).toNumber();
        }
        if (info.currentHeartRate != null) {
            seed += info.currentHeartRate;
        }
        if (info.elapsedDistance != null) {
            seed += (info.elapsedDistance / 20.0f).toNumber();
        }
        return seed;
    }

    private function isRecentMessage(message as String) as Boolean {
        for (var i = 0; i < _recentMessages.size(); i += 1) {
            if (_recentMessages[i] == message) {
                return true;
            }
        }
        return false;
    }

    private function rememberMessage(message as String) as Void {
        if (_recentMessages.size() > 0) {
            var lastIndex = _recentMessages.size() - 1;
            if (_recentMessages[lastIndex] == message) {
                return;
            }
        }

        _recentMessages.add(message);
        while (_recentMessages.size() > RECENT_MESSAGE_WINDOW) {
            _recentMessages.remove(0);
        }
    }

    private function pickNonDuplicateCategoryMessage(
        info as Activity.Info,
        stateKey as String,
        category as String
    ) as String {
        var seed = buildMessagePickSeed(info, stateKey);
        for (var i = 0; i < CATEGORY_PICK_ATTEMPTS; i += 1) {
            var candidate = pickCategoryMessage(category, stateKey, seed + i);
            if (!isRecentMessage(candidate) || candidate == _displayMessage) {
                return candidate;
            }
        }

        return pickCategoryMessage(category, stateKey, seed);
    }

    private function applyMessageUpdate(
        candidate as String,
        nowMs as Number?,
        forceUpdate as Boolean
    ) as String {
        if (!forceUpdate && _lastMessageUpdateMs != null && nowMs != null) {
            if ((nowMs - _lastMessageUpdateMs) < MIN_MESSAGE_UPDATE_MS) {
                return _displayMessage;
            }
        }

        if (!forceUpdate && candidate != _displayMessage && isRecentMessage(candidate)) {
            return _displayMessage;
        }

        var changed = candidate != _displayMessage;
        if (changed) {
            _displayMessage = candidate;
            rememberMessage(candidate);
        }

        if ((changed || forceUpdate || _lastMessageUpdateMs == null) && nowMs != null) {
            _lastMessageUpdateMs = nowMs;
        }

        return _displayMessage;
    }

    private function pickFixedMessage(stateKey as String) as String {
        switch (stateKey) {
            case "UP_Z1":
                return "Save on climbs";
            case "UP_Z2":
                return "Use your arms";
            case "UP_Z3":
                return "Pull with arms";
            case "UP_Z4":
                return "Ease up now";
            case "UP_Z5":
                return "Back off now";
            case "FL_Z1":
                return "Easy and smooth";
            case "FL_Z2":
                return "Hold target pace";
            case "FL_Z3":
                return "Deep breaths";
            case "FL_Z4":
                return "Too fast, relax";
            case "FL_Z5":
                return "Slow down once";
            case "DN_Z1":
                return "Form on downhill";
            case "DN_Z2":
                return "Soft landing";
            case "DN_Z3":
                return "Dont over-speed";
            case "DN_Z4":
                return "Over pace";
            case "DN_Z5":
                return "Danger, back off";
        }

        return "Waiting HR";
    }

    function compute(info as Activity.Info) as Numeric or Duration or String or Null {
        // Step 6: prevent fast flicker and avoid recent duplicate messages.
        var nowMs = info.timerTime;
        var zone = zoneFromHeartRate(info.currentHeartRate);
        var slope = updateSlopeState(info.altitude, info.elapsedDistance);
        var stateKey = buildStateKey(slope, zone);
        var distMessage = detectDistanceEvent(info.elapsedDistance);
        if (distMessage != null) {
            return applyMessageUpdate(distMessage, nowMs, true);
        }
        var category = pickTrainingCategory(info, stateKey);
        var categoryMessage = pickNonDuplicateCategoryMessage(info, stateKey, category);
        return applyMessageUpdate(categoryMessage, nowMs, false);
    }
}
