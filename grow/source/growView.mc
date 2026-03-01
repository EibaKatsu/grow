import Toybox.Activity;
import Toybox.WatchUi;

class growView extends WatchUi.SimpleDataField {

    function initialize() {
        SimpleDataField.initialize();
        label = "Grow";
    }

    function compute(info as Activity.Info) as Numeric or Duration or String or Null {
        // Keep MVP stable with a constant value; this will be replaced
        // with step-based growth logic incrementally.
        return "Grow";
    }
}
