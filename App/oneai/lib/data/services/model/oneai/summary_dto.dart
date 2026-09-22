import 'package:freezed_annotation/freezed_annotation.dart';

part 'summary_dto.freezed.dart';

part 'summary_dto.g.dart';

@freezed
sealed class SummaryDto with _$SummaryDto {
  const factory SummaryDto({
    String? summaryText,
    String? icon,
    String? title,
    String? type,
    List<SummarySectionDto>? sections,
  }) = _SummaryDto;

  factory SummaryDto.fromJson(Map<String, dynamic> json) => _$SummaryDtoFromJson(json);
}

@freezed
sealed class SummarySectionDto with _$SummarySectionDto {
  const factory SummarySectionDto({String? title, String? timeRange, List<String>? bullets}) = _SummarySectionDto;

  factory SummarySectionDto.fromJson(Map<String, dynamic> json) => _$SummarySectionDtoFromJson(json);
}
