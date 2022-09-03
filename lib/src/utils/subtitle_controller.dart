import 'dart:async';

import '../core/exceptions.dart';
import '../core/models.dart';
import 'subtitle_parser.dart';
import 'subtitle_provider.dart';
import 'types.dart';

/// The base class of all subtitles controller object.
abstract class ISubtitleController {
  //! Final fields
  /// Store the subtitle provider.
  final SubtitleProvider _provider;

  /// Store the subtitles objects after decoded.
  final List<Subtitle> subtitles;

  //! Later and Nullable fields
  /// The parser class, maybe still null if you are not initial the controller.
  ISubtitleParser? _parser;

  ISubtitleController({
    required SubtitleProvider provider,
  })  : _provider = provider,
        subtitles = List.empty(growable: true);

  //! Getters

  /// Get the parser class
  ISubtitleParser get parser {
    if (initialized) return _parser!;
    throw NotInitializedException();
  }

  /// Return the current subtitle provider
  SubtitleProvider get provider => _provider;

  /// Check it the controller is initial or not.
  bool initialized = false;

  //! Abstract methods
  /// Use this method to customize your search algorithm.
  Subtitle? durationSearch(Duration duration);

  /// To get one or more subtitles in same duration range.
  List<Subtitle> multiDurationSearch(Duration duration);

  List<Subtitle> flattenSubtitles(List<Subtitle> subtitleList) {
    for (var i = 1; i < subtitleList.length; i++) {
      var previousSubtitle = subtitleList[i - 1];
      var currentSubtitle = subtitleList[i];

      if (previousSubtitle.start == currentSubtitle.start &&
          previousSubtitle.end == currentSubtitle.end) {
        // Recombine only if they are not the same subtitle
        var newSubtitle = Subtitle(
          data: previousSubtitle.data == currentSubtitle.data
              ? '${previousSubtitle.data}'
              : '${previousSubtitle.data}\n${currentSubtitle.data}',
          start: currentSubtitle.start,
          end: currentSubtitle.end,
          index: previousSubtitle.index,
        );

        subtitleList.insert(i, newSubtitle);
        subtitleList.remove(previousSubtitle);
        subtitleList.remove(currentSubtitle);
      }
    }

    // Attempt this recombination a lot to stamp out stubborn repeats
    // This is not the best way to do this
    for (var i = 0; i < 3; i++) {
      // Recombine subtitles if they are the same value and next to each other
      for (var i = 1; i < subtitleList.length; i++) {
        var previousSubtitle = subtitleList[i - 1];
        var currentSubtitle = subtitleList[i];

        if (previousSubtitle.data == currentSubtitle.data &&
            previousSubtitle.end.inMilliseconds ==
                currentSubtitle.start.inMilliseconds) {
          var newSubtitle = Subtitle(
            data: '${previousSubtitle.data}',
            start: previousSubtitle.start,
            end: currentSubtitle.end,
            index: previousSubtitle.index,
          );

          subtitleList.insert(i, newSubtitle);
          subtitleList.remove(previousSubtitle);
          subtitleList.remove(currentSubtitle);
        }
      }

      // Recombine subtitles if they are the same value and next to each other
      for (var i = 1; i < subtitleList.length; i++) {
        var previousSubtitle = subtitleList[i - 1];
        var currentSubtitle = subtitleList[i];

        if (previousSubtitle.data == currentSubtitle.data &&
            500 >
                (currentSubtitle.start.inMilliseconds -
                    previousSubtitle.end.inMilliseconds)) {
          var newSubtitle = Subtitle(
            data: '${previousSubtitle.data}',
            start: previousSubtitle.start,
            end: currentSubtitle.end,
            index: previousSubtitle.index,
          );

          subtitleList.insert(i, newSubtitle);
          subtitleList.remove(previousSubtitle);
          subtitleList.remove(currentSubtitle);
        }
      }

      if (subtitleList.length >= 2) {
        Subtitle secondLastSubtitle = subtitleList[subtitleList.length - 2];
        Subtitle lastSubtitle = subtitleList[subtitleList.length - 1];
        if (lastSubtitle.end.inMilliseconds <
            secondLastSubtitle.start.inMilliseconds) {
          subtitleList.remove(lastSubtitle);
        }
      }

      for (int i = 0; i < subtitleList.length; i++) {
        subtitleList[i].index = i + 1;
        subtitleList[i].data = sanitizeSubtitleArtifacts(subtitleList[i].data);
      }
    }

    return subtitleList;
  }

  String sanitizeSubtitleArtifacts(String unsanitizedContent) {
    RegExp exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);

    String sanitizedContent = unsanitizedContent.replaceAll(exp, '');
    sanitizedContent = sanitizedContent.replaceAll(
        RegExp(r'{(.*?)}', caseSensitive: false), '');

    sanitizedContent = sanitizedContent.replaceAll("<br>", "\n");
    sanitizedContent = sanitizedContent.replaceAll('&amp;', '&');
    sanitizedContent = sanitizedContent.replaceAll('&apos;', '\'');
    sanitizedContent = sanitizedContent.replaceAll('&#39;', '\'');
    sanitizedContent = sanitizedContent.replaceAll('&quot;', '\"');
    sanitizedContent = sanitizedContent.replaceAll('&amp;', '');
    sanitizedContent = sanitizedContent.replaceAll('\\n', '\n');
    sanitizedContent = sanitizedContent.replaceAll('​', '');

    return sanitizedContent;
  }

  //! Virual methods
  Future<void> initial() async {
    if (initialized) return;
    final providerObject = await _provider.getSubtitle();
    _parser = SubtitleParser(providerObject);

    List<Subtitle> parsed = [];
    if (_parser!.object.type != SubtitleType.srt) {
      parsed = _parser!.parsing();
    } else {
      parsed = getSubtitlesData(providerObject.data);
    }

    List<Subtitle> flattened = flattenSubtitles(parsed);
    subtitles.addAll(flattened);

    sort();
    initialized = true;
  }

  /// Sort all subtitles object from smaller duration to larger duration.
  void sort() => subtitles.sort((s1, s2) => s1.compareTo(s2));

  /// Get all subtitles as a single string, you can separate between subtitles
  /// using `separator`, the default is `, `.
  String getAll([String separator = ', ']) => subtitles.join(separator);
}

// Straight from flutter_subtitle_wrapper
List<Subtitle> getSubtitlesData(
  String subtitlesContent,
) {
  RegExp regExp = RegExp(
    r'((\d{2}):(\d{2}):(\d{2})\,(\d+)) +--> +((\d{2}):(\d{2}):(\d{2})\,(\d{3})).*[\r\n]+\s*(.*(?:\r?\n(?!\r?\n).*)*)',
    caseSensitive: false,
    multiLine: true,
  );

  final matches = regExp.allMatches(subtitlesContent).toList();
  final List<Subtitle> subtitleList = [];

  for (final RegExpMatch regExpMatch in matches) {
    final startTimeHours = int.parse(regExpMatch.group(2)!);
    final startTimeMinutes = int.parse(regExpMatch.group(3)!);
    final startTimeSeconds = int.parse(regExpMatch.group(4)!);
    final startTimeMilliseconds = int.parse(regExpMatch.group(5)!);

    final endTimeHours = int.parse(regExpMatch.group(7)!);
    final endTimeMinutes = int.parse(regExpMatch.group(8)!);
    final endTimeSeconds = int.parse(regExpMatch.group(9)!);
    final endTimeMilliseconds = int.parse(regExpMatch.group(10)!);
    final text = regExpMatch.group(11);

    final startTime = Duration(
        hours: startTimeHours,
        minutes: startTimeMinutes,
        seconds: startTimeSeconds,
        milliseconds: startTimeMilliseconds);
    final endTime = Duration(
        hours: endTimeHours,
        minutes: endTimeMinutes,
        seconds: endTimeSeconds,
        milliseconds: endTimeMilliseconds);

    subtitleList.add(
      Subtitle(
        start: startTime,
        end: endTime,
        data: text ?? "",
        index: subtitleList.length + 1,
      ),
    );
  }

  return subtitleList;
}

/// The default class to controller subtitles, you can use it or extends
/// [ISubtitleController] to create your custom.
class SubtitleController extends ISubtitleController {
  SubtitleController({
    required SubtitleProvider provider,
  }) : super(provider: provider);

  /// Fetch your current single subtitle value by providing the duration.
  @override
  Subtitle? durationSearch(Duration duration) {
    if (!initialized) throw NotInitializedException();

    final l = 0;
    final r = subtitles.length - 1;

    var index = _binarySearch(l, r, duration);

    if (index > -1) {
      return subtitles[index];
    }
  }

  /// Perform binary search when search about subtitle by duration.
  int _binarySearch(int l, int r, Duration duration) {
    if (r >= l) {
      var mid = l + (r - l) ~/ 2;

      if (subtitles[mid].inRange(duration)) return mid;

      // If element is smaller than mid, then
      // it can only be present in left subarray
      if (subtitles[mid].isLarg(duration)) {
        return _binarySearch(mid + 1, r, duration);
      }

      // Else the element can only be present
      // in right subarray
      return _binarySearch(l, mid - 1, duration);
    }

    // We reach here when element is not present
    // in array
    return -1;
  }

  @override
  List<Subtitle> multiDurationSearch(Duration duration) {
    var correctSubtitles = List<Subtitle>.empty(growable: true);

    subtitles.forEach((value) {
      if (value.inRange(duration)) correctSubtitles.add(value);
    });

    return correctSubtitles;
  }
}
