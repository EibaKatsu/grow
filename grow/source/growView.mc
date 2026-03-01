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
    private const TRAINING_MIN_UPDATE_MS = 5000;
    private const RACE_MIN_UPDATE_BASE_MS = 20000;
    private const RACE_MIN_UPDATE_SPAN_MS = 10000;
    private const RECENT_MESSAGE_WINDOW = 5;
    private const CATEGORY_PICK_ATTEMPTS = 6;
    private const DISPLAY_MAX_CHARS = 18;
    private const DISPLAY_ELLIPSIS = "...";

    private var _lastAltitude as Float?;
    private var _lastDistance as Float?;
    private var _slopeState as String;
    private var _lastKmEvent as Float;
    private var _lastSeenDistanceKm as Float?;
    private var _distEventCount as Number;
    private var _displayMessage as String;
    private var _lastMessageUpdateMs as Number?;
    private var _recentMessages as Array<String>;
    private var _pendingDistMessage as String?;

    function initialize() {
        SimpleDataField.initialize();
        label = "HR Zone";
        _lastAltitude = null;
        _lastDistance = null;
        _slopeState = "FL";
        _lastKmEvent = 0.0f;
        _lastSeenDistanceKm = null;
        _distEventCount = 0;
        _displayMessage = "Grow";
        _lastMessageUpdateMs = null;
        _recentMessages = [] as Array<String>;
        _pendingDistMessage = null;
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

    private function pickRaceCategory(info as Activity.Info, stateKey as String) as String {
        // Step 8 ratio target:
        // FIXED 55 / PRAISE 25 / WARN 15 / FUNNY 5
        var bucketSource = stateKeyCode(stateKey) * 11;

        if (info.timerTime != null) {
            bucketSource += (info.timerTime / 10000).toNumber();
        }
        if (info.currentHeartRate != null) {
            bucketSource += info.currentHeartRate;
        }
        if (info.elapsedDistance != null) {
            bucketSource += (info.elapsedDistance / 40.0f).toNumber();
        }

        var bucket = bucketSource % 100;
        if (bucket < 55) {
            return "FIXED";
        } else if (bucket < 80) {
            return "PRAISE";
        } else if (bucket < 95) {
            return "WARN";
        }

        return "FUNNY";
    }

    (:trainingMode)
    private function getAppMode() as String {
        return "TRAINING";
    }

    (:raceMode)
    private function getAppMode() as String {
        return "RACE";
    }

    private function isRaceMode() as Boolean {
        return getAppMode() == "RACE";
    }

    private function isRaceWarningState(stateKey as String) as Boolean {
        switch (stateKey) {
            case "UP_Z5":
            case "FL_Z5":
            case "DN_Z5":
   
            case "DN_Z4":
                return true;
        }

        return false;
    }

    private function raceMinUpdateMs(stateKey as String) as Number {
        var offset = (stateKeyCode(stateKey) * 137) % (RACE_MIN_UPDATE_SPAN_MS + 1);
        return RACE_MIN_UPDATE_BASE_MS + offset;
    }

    private function minUpdateMsForMode(stateKey as String) as Number {
        if (isRaceMode()) {
            return raceMinUpdateMs(stateKey);
        }

        return TRAINING_MIN_UPDATE_MS;
    }

    private function pickCategoryMessage(category as String, stateKey as String, variant as Number) as String {
        var idx = variant % 3;
        switch (category) {
            case "FIXED":
                return pickFixedMessage(stateKey);
            case "WARN":
                if (idx == 0) {
                    return "今は落とそう";
                } else if (idx == 1) {
                    return "熱すぎる、整え";
                }
                return "制御優先で";
            case "FUNNY":
                if (idx == 0) {
                    return "気楽にいこう";
                } else if (idx == 1) {
                    return "顔の力ぬいて";
                }
                return "笑って流そう";
            case "SALT":
                if (idx == 0) {
                    return "集中きらすな";
                } else if (idx == 1) {
                    return "ペース見直し";
                }
                return "リズム固定で";
            case "ALCOHOL":
                if (idx == 0) {
                    return "まずは水やで";
                } else if (idx == 1) {
                    return "フラつく走りはいらん";
                }
                return "ちび水で進め";
            case "TOXIC":
                if (idx == 0) {
                    return "言い訳なしで";
                } else if (idx == 1) {
                    return "まだいける";
                }
                return "折れずにいけ";
            case "PRAISE":
                if (idx == 0) {
                    return "ようやってる";
                } else if (idx == 1) {
                    return "制御うまい";
                }
                return "ええ我慢や";
        }

        return pickFixedMessage(stateKey);
    }

    private function formatDistanceMarker(markerKm as Float) as String {
        var scaled = ((markerKm * 10.0f) + 0.5f).toNumber();
        var whole = scaled / 10;
        var decimal = scaled % 10;

        if (decimal == 0) {
            return whole.toString();
        }

        return whole.toString() + "." + decimal.toString();
    }

    private function distanceMessagesForKey(markerKey as String) as Array<String> or Null {
        switch (markerKey) {
            case "1": return ["1キロ突破やで。ええ入り！", "1キロやん。肩の力ぬこ"];
            case "2": return ["2キロ。まだ余裕あるやろ", "2キロ到達。ええペースやん"];
            case "3": return ["3キロ。リズムそのままやで", "3キロ、ええ感じに温まったな"];
            case "4": return ["4キロ。焦らんでええよ", "4キロ。呼吸、ゆったりな"];
            case "5": return ["もう5キロやん、早っ！", "5キロ到達。余裕顔いけるで", "5キロ。ここからが本番やな"];
            case "6": return ["6キロ。ええ流れ続いてるで", "6キロ。力みゼロでいこ"];
            case "7": return ["7キロ。ピッチだけ意識な", "7キロ。顔、ゆるめとこ"];
            case "8": return ["8キロ。ええやん、その安定感", "8キロ。淡々が最強やで"];
            case "9": return ["9キロ。次で10や、落ち着け", "9キロ。呼吸深うな"];
            case "10": return ["10キロ到達。調子ええな", "10キロ。まだまだいけるやろ", "10キロ。水いこ、水"];
            case "11": return ["11キロ。まだ序盤の顔でいこ", "11キロ。今は温存やで"];
            case "12": return ["12キロ。リズム勝ちやな", "12キロ。肩、落としてこ"];
            case "13": return ["13キロ。ええ感じにしんどいな", "13キロ。雑にならんで"];
            case "14": return ["14キロ。足、回すだけでええ", "14キロ。次、15やで"];
            case "15": return ["15キロ。ええ積み上げやで", "15キロ。足、よう動いとる", "15キロ。ここは丁寧にいこ"];
            case "16": return ["16キロ。ここで焦らんとこ", "16キロ。淡々続けよ"];
            case "17": return ["17キロ。ええやん、粘れてる", "17キロ。水、そろそろやで"];
            case "18": return ["18キロ。フォーム、きれいめ意識", "18キロ。余計な力いらん"];
            case "19": return ["19キロ。20見えた、落ち着こ", "19キロ。呼吸、整えよ"];
            case "20": return ["20キロ。半分見えてきたで", "20キロ。焦らず貯金や", "20キロ。いったん整えよ"];
            case "21": return ["21キロ。次でハーフやで", "21キロ。落ち着いて刻も"];
            case "21.1": return ["ハーフ超えた！ここから味や", "21.1。後半戦、入るで", "ハーフ通過。落ち着いていこ"];
            case "22": return ["22キロ。ここから大人の走りや", "22キロ。上げんでええで"];
            case "23": return ["23キロ。一定、一定やで", "23キロ。心拍、暴れたらアカン"];
            case "24": return ["24キロ。まだいける、まだいける", "24キロ。足、丁寧にな"];
            case "25": return ["25キロ。ここで雑にならんとこ", "25キロ。補給、忘れてへん？", "25キロ。えらい、ほんまえらい"];
            case "26": return ["26キロ。しんどいの普通やで", "26キロ。呼吸、深う"];
            case "27": return ["27キロ。今は守りで勝つ", "27キロ。水いこ、水"];
            case "28": return ["28キロ。焦らん。淡々や", "28キロ。腕、軽く振ろ"];
            case "29": return ["29キロ。次で30や、整えよ", "29キロ。フォーム戻そか"];
            case "30": return ["30キロ。ここ踏ん張れたら勝ちや", "30キロ。勝負どころ来たで", "30キロ。呼吸整えて、いこ"];
            case "31": return ["31キロ。いまが踏ん張り所や", "31キロ。崩れんでええ"];
            case "32": return ["32キロ。無理せんで強いぞ", "32キロ。呼吸からやで"];
            case "33": return ["33キロ。雑になりやすい、注意", "33キロ。足音、静かに"];
            case "34": return ["34キロ。あと少しずつ、刻も", "34キロ。ここ耐えよ"];
            case "35": return ["35キロ。ようやっとる、マジで", "35キロ。崩れんでええで", "35キロ。あと少しずつや"];
            case "36": return ["36キロ。えらい、ほんまに", "36キロ。いったん整えよ"];
            case "37": return ["37キロ。いま勝ってるで", "37キロ。崩れたら戻そ"];
            case "38": return ["38キロ。小さく攻めよ", "38キロ。呼吸、落ち着け"];
            case "39": return ["39キロ。次で40、いける", "39キロ。あとちょいずつ"];
            case "40": return ["40キロ。あとちょい、いこ", "40キロ。もうゴール見えてるで", "40キロ。最後、丁寧にな"];
            case "41": return ["41キロ。あと1キロやで！", "41キロ。最後、丁寧にいこ"];
            case "42": return ["42キロ。あと200m、いける！", "42キロ。ラスト刻め！"];
            case "42.2": return ["完走や！ほんまにやったな", "42.2。えぐい。拍手やで", "ゴール！今日の主役、きみや"];
        }

        return null;
    }

    private function buildDistanceEventMessage(markerKm as Float, eventCount as Number) as String {
        var markerKey = formatDistanceMarker(markerKm);
        var messages = distanceMessagesForKey(markerKey);
        if (messages != null && messages.size() > 0) {
            var idx = eventCount % messages.size();
            return messages[idx];
        }

        return markerKey + "km 通過";
    }

    private function detectDistanceEvent(elapsedDistance as Float?) as String or Null {
        if (elapsedDistance == null) {
            return null;
        }

        var distanceKm = elapsedDistance / 1000.0f;
        if (_lastSeenDistanceKm != null && (distanceKm + DIST_EVENT_TOLERANCE_KM) < _lastSeenDistanceKm) {
            // Activity restarted or playback seeked back.
            _lastKmEvent = 0.0f;
            _distEventCount = 0;
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
            _distEventCount += 1;
            return buildDistanceEventMessage(crossedMarker, _distEventCount);
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

    private function trimForDisplay(message as String) as String {
        if (message.length() <= DISPLAY_MAX_CHARS) {
            return message;
        }

        var keepChars = DISPLAY_MAX_CHARS - DISPLAY_ELLIPSIS.length();
        if (keepChars <= 0) {
            return DISPLAY_ELLIPSIS;
        }

        return message.substring(0, keepChars) + DISPLAY_ELLIPSIS;
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
        if (_recentMessages.size() > RECENT_MESSAGE_WINDOW) {
            var start = _recentMessages.size() - RECENT_MESSAGE_WINDOW;
            var trimmed = [] as Array<String>;
            for (var i = start; i < _recentMessages.size(); i += 1) {
                trimmed.add(_recentMessages[i]);
            }
            _recentMessages = trimmed;
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
            var displayCandidate = trimForDisplay(candidate);
            if (!isRecentMessage(displayCandidate) || displayCandidate == _displayMessage) {
                return candidate;
            }
        }

        return pickCategoryMessage(category, stateKey, seed);
    }

    private function applyMessageUpdate(
        candidate as String,
        nowMs as Number?,
        forceUpdate as Boolean,
        minUpdateMs as Number
    ) as String {
        var displayCandidate = trimForDisplay(candidate);

        if (!forceUpdate && _lastMessageUpdateMs != null && nowMs != null) {
            if ((nowMs - _lastMessageUpdateMs) < minUpdateMs) {
                return _displayMessage;
            }
        }

        if (!forceUpdate && displayCandidate != _displayMessage && isRecentMessage(displayCandidate)) {
            return _displayMessage;
        }

        var changed = displayCandidate != _displayMessage;
        if (changed) {
            _displayMessage = displayCandidate;
            rememberMessage(displayCandidate);
        }

        if ((changed || forceUpdate || _lastMessageUpdateMs == null) && nowMs != null) {
            _lastMessageUpdateMs = nowMs;
        }

        return _displayMessage;
    }

    private function pickFixedMessage(stateKey as String) as String {
        switch (stateKey) {
            case "UP_Z1":
                return "上り温存で";
            case "UP_Z2":
                return "腕で押そう";
            case "UP_Z3":
                return "腕振り強め";
            case "UP_Z4":
                return "少し落とそう";
            case "UP_Z5":
                return "今は下げる";
            case "FL_Z1":
                return "楽に滑らか";
            case "FL_Z2":
                return "目標ペース";
            case "FL_Z3":
                return "深く呼吸";
            case "FL_Z4":
                return "速い、落ち着け";
            case "FL_Z5":
                return "一段下げよう";
            case "DN_Z1":
                return "下りも丁寧";
            case "DN_Z2":
                return "接地やわらかく";
            case "DN_Z3":
                return "下り飛ばしすぎ";
            case "DN_Z4":
                return "オーバーペース";
            case "DN_Z5":
                return "危険、下げて";
        }

        return "心拍待ち";
    }

    function compute(info as Activity.Info) as Numeric or Duration or String or Null {
        // Step 8: Race mode adds WARN priority and slower update cadence.
        var nowMs = System.getTimer();
        var zone = zoneFromHeartRate(info.currentHeartRate);
        var slope = updateSlopeState(info.altitude, info.elapsedDistance);
        var stateKey = buildStateKey(slope, zone);
        var minUpdateMs = minUpdateMsForMode(stateKey);
        var distMessage = detectDistanceEvent(info.elapsedDistance);

        if (isRaceMode()) {
            if (distMessage != null) {
                _pendingDistMessage = distMessage;
            }

            if (isRaceWarningState(stateKey)) {
                var warnMessage = pickNonDuplicateCategoryMessage(info, stateKey, "WARN");
                return applyMessageUpdate(warnMessage, nowMs, true, minUpdateMs);
            }

            if (_pendingDistMessage != null) {
                var pendingDistMessage = _pendingDistMessage;
                _pendingDistMessage = null;
                return applyMessageUpdate(pendingDistMessage, nowMs, true, minUpdateMs);
            }
        } else if (distMessage != null) {
            return applyMessageUpdate(distMessage, nowMs, true, minUpdateMs);
        }

        var category = pickTrainingCategory(info, stateKey);
        if (isRaceMode()) {
            category = pickRaceCategory(info, stateKey);
        }
        var categoryMessage = pickNonDuplicateCategoryMessage(info, stateKey, category);
        return applyMessageUpdate(categoryMessage, nowMs, false, minUpdateMs);
    }
}
