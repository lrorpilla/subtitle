import 'package:flutter/foundation.dart';

import '../core/exceptions.dart';
import '../core/models.dart';
import 'regexes.dart';
import 'types.dart';

/// It is used to analyze and convert subtitle files into software objects that are
/// viewable and usable. The base class of [SubtitleParser], you can create your
/// custom by extends from this base class.
abstract class ISubtitleParser {
  /// The subtitle object that contain subtitle info (file data and format type).
  final SubtitleObject object;

  const ISubtitleParser(this.object);

  /// Getter method to return the current [SubtitleRegexObject] of this [object].
  SubtitleRegexObject get regexObject;

  /// Abstract method parsing the data from any format and return it as a list of
  /// subtitles.
  Future<List<Subtitle>> parsing();

  /// Normalize the text data of subtitle, remove unnecessary characters.
  String normalize(String txt) {
    return txt
        .replaceAll(RegExp(r'<\/?[\w.]+\/?>|\n| {2,}'), ' ')
        .replaceAll(RegExp(r' {2,}'), ' ')
        .trim();
  }
}

class ParserIsolateParams {
  ParserIsolateParams({
    required this.data,
    required this.regExp,
    required this.type,
  });

  final String data;
  final RegExp regExp;
  final SubtitleType type;
}

Future<List<Subtitle>> parseSubtitles(ParserIsolateParams params) async {
  final regExp = params.regExp;
  var matches = regExp.allMatches(params.data);

  var subtitles = List<Subtitle>.empty(growable: true);

  for (var i = 0; i < matches.length; i++) {
    var matcher = matches.elementAt(i);

    var index = i + 1;
    if (params.type == SubtitleType.vtt || params.type == SubtitleType.srt) {
      index = int.parse(matcher.group(1) ?? '${i + 1}');
    }

    var startMins = 0;
    var startHours = 0;
    if (matcher.group(3) == null && matcher.group(2) != null) {
      startMins = int.parse(matcher.group(2)?.replaceAll(':', '') ?? '0');
    } else {
      startMins = int.parse(matcher.group(3)?.replaceAll(':', '') ?? '0');
      startHours = int.parse(matcher.group(2)?.replaceAll(':', '') ?? '0');
    }

    var start = Duration(
      seconds: int.parse(matcher.group(4)?.replaceAll(':', '') ?? '0'),
      minutes: startMins,
      hours: startHours,
      milliseconds: int.parse(matcher.group(5) ?? '0'),
    );

    var endMins = 0;
    var endHours = 0;

    if (matcher.group(7) == null && matcher.group(6) != null) {
      endMins = int.parse(matcher.group(6)?.replaceAll(':', '') ?? '0');
    } else {
      endMins = int.parse(matcher.group(7)?.replaceAll(':', '') ?? '0');
      endHours = int.parse(matcher.group(6)?.replaceAll(':', '') ?? '0');
    }

    var end = Duration(
      seconds: int.parse(matcher.group(8)?.replaceAll(':', '') ?? '0'),
      minutes: endMins,
      hours: endHours,
      milliseconds: int.parse(matcher.group(9) ?? '0'),
    );

    final data = matcher.group(11)?.trim() ?? '';

    subtitles.add(Subtitle(
      start: start,
      end: end,
      data: data,
      index: index,
    ));
  }

  return subtitles;
}

/// Usable class to parsing subtitle file. It is used to analyze and convert subtitle
/// files into software objects that are viewable and usable.
class SubtitleParser extends ISubtitleParser {
  const SubtitleParser(SubtitleObject object) : super(object);

  @override
  SubtitleRegexObject get regexObject {
    switch (object.type) {
      case SubtitleType.vtt:
        return SubtitleRegexObject.vtt();
      case SubtitleType.srt:
        return SubtitleRegexObject.srt();
      case SubtitleType.ttml:
      case SubtitleType.dfxp:
        return SubtitleRegexObject.ttml();
      default:
        throw UnsupportedSubtitleFormat();
    }
  }

  @override
  Future<List<Subtitle>> parsing({
    bool shouldNormalizeText = true,
  }) async {
    /// Stored variable for subtitles.
    final pattern = regexObject.pattern;

    var regExp = RegExp(pattern);
    var params = ParserIsolateParams(
      data: object.data,
      regExp: regExp,
      type: regexObject.type,
    );

    return await compute(parseSubtitles, params);
  }
}

/// Used in [CustomSubtitleParser] to comstmize parsing of subtitles.
typedef OnParsingSubtitle = List<Subtitle> Function(
    Iterable<RegExpMatch> matchers);

/// Customizable subtitle parser, for custom regexes. You can provide your
/// regex in [pattern], and custom decode in [onParsing].
class CustomSubtitleParser extends ISubtitleParser {
  /// Store the custom regexp of subtitle.
  final String pattern;

  /// Decoding the subtitles and return a list from result.
  final OnParsingSubtitle onParsing;

  const CustomSubtitleParser({
    required SubtitleObject object,
    required this.pattern,
    required this.onParsing,
  }) : super(object);

  @override
  Future<List<Subtitle>> parsing() async {
    var regExp = RegExp(regexObject.pattern);
    var matches = regExp.allMatches(object.data);
    return onParsing(matches);
  }

  @override
  SubtitleRegexObject get regexObject => SubtitleRegexObject.custom(pattern);
}
