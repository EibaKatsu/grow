import Toybox.Activity;
import Toybox.Lang;
import Toybox.Time;
import Toybox.WatchUi;

class growView extends WatchUi.SimpleDataField {
    private const HR_MAX_DEFAULT = 190.0f;

    function initialize() {
        SimpleDataField.initialize();
        label = "HR Zone";
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

    function compute(info as Activity.Info) as Numeric or Duration or String or Null {
        // Step 1: heart rate zone only. Keep output format as "Zx".
        return zoneFromHeartRate(info.currentHeartRate);
    }
}
