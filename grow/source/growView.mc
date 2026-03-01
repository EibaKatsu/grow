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

    private var _lastAltitude as Float?;
    private var _lastDistance as Float?;
    private var _slopeState as String;

    function initialize() {
        SimpleDataField.initialize();
        label = "HR Zone";
        _lastAltitude = null;
        _lastDistance = null;
        _slopeState = "FL";
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

    private function pickCategoryMessage(category as String, stateKey as String) as String {
        switch (category) {
            case "FIXED":
                return pickFixedMessage(stateKey);
            case "FUNNY":
                return "Keep it light";
            case "SALT":
                return "Stay sharp";
            case "ALCOHOL":
                return "Water first";
            case "TOXIC":
                return "No excuses";
            case "PRAISE":
                return "Strong work";
        }

        return pickFixedMessage(stateKey);
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
        // Step 4: choose category by Training ratio, then pick message.
        var zone = zoneFromHeartRate(info.currentHeartRate);
        var slope = updateSlopeState(info.altitude, info.elapsedDistance);
        var stateKey = buildStateKey(slope, zone);
        var category = pickTrainingCategory(info, stateKey);
        return pickCategoryMessage(category, stateKey);
    }
}
