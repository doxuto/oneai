import 'package:freezed_annotation/freezed_annotation.dart';

part 'summary_model.freezed.dart';
part 'summary_model.g.dart';

@freezed
sealed class Summary with _$Summary {
  const factory Summary({
    String? summaryText,
    String? icon,
    String? title,
    String? type,
    List<SummarySection>? sections,
  }) = _Summary;

  factory Summary.fromJson(Map<String, dynamic> json) => _$SummaryFromJson(json);
}

@freezed
sealed class SummarySection with _$SummarySection {
  const factory SummarySection({String? timeRange, String? title, List<String>? bullets}) = _SummarySection;

  factory SummarySection.fromJson(Map<String, dynamic> json) => _$SummarySectionFromJson(json);
}
