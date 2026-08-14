import 'package:flutter/material.dart';

import '../api/imdb_api_exception.dart';
import '../models/title_details.dart';
import '../models/title_summary.dart';
import '../repositories/imdb_repository.dart';

class TitlePreviewPage extends StatefulWidget {
  const TitlePreviewPage({
    super.key,
    required this.summary,
    required this.repository,
  });

  final TitleSummary summary;
  final ImdbRepository repository;

  @override
  State<TitlePreviewPage> createState() => _TitlePreviewPageState();
}

class _TitlePreviewPageState extends State<TitlePreviewPage> {
  late final Future<TitleDetails?> _detailsFuture;

  @override
  void initState() {
    super.initState();
    _detailsFuture = _loadDetails();
  }

  Future<TitleDetails?> _loadDetails() async {
    final details = await widget.repository.titleDetails([widget.summary.id]);
    return details.isEmpty ? null : details.first;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(widget.summary.title)),
        body: SafeArea(
          child: FutureBuilder<TitleDetails?>(
            future: _detailsFuture,
            builder: (context, snapshot) {
              final details = snapshot.data;
              final loading = snapshot.connectionState != ConnectionState.done;
              final error = snapshot.error;

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _Header(summary: widget.summary, details: details),
                  const SizedBox(height: 16),
                  if (loading) const LinearProgressIndicator(),
                  if (error != null) _ErrorBox(error: error),
                  if (!loading && error == null && details == null)
                    const _EmptyBox(),
                  if (details != null) _DetailsBody(details: details),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.summary, required this.details});

  final TitleSummary summary;
  final TitleDetails? details;

  @override
  Widget build(BuildContext context) {
    final imageUrl = details?.imageUrl ?? summary.imageUrl;
    final type = details?.type ?? summary.type;
    final year = details?.yearLabel ?? summary.yearLabel;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Poster(url: imageUrl),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                details?.title ?? summary.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                [summary.id, ?type, if (year.isNotEmpty) year].join(' / '),
                textDirection: TextDirection.ltr,
              ),
              if (details?.rating != null || summary.rating != null) ...[
                const SizedBox(height: 8),
                Text(
                  'امتیاز IMDb: ${_rating(details?.rating ?? summary.rating)}',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailsBody extends StatelessWidget {
  const _DetailsBody({required this.details});

  final TitleDetails details;

  @override
  Widget build(BuildContext context) {
    final runtime = details.runtimeMinutes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (details.plot != null) ...[
          _SectionTitle('خلاصه داستان'),
          Text(details.plot!),
          const SizedBox(height: 16),
        ],
        _InfoGrid(
          rows: [
            _InfoRow('عنوان اصلی', details.originalTitle),
            _InfoRow('ژانر', details.genres.join(', ')),
            _InfoRow('تاریخ انتشار', details.releaseDate),
            _InfoRow('مدت زمان', runtime == null ? null : '$runtime دقیقه'),
            _InfoRow('رده‌بندی', details.certificate),
            _InfoRow('وضعیت انتشار', details.productionStatus),
          ],
        ),
      ],
    );
  }
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.rows});

  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    final visibleRows = rows.where((row) => row.value.trim().isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in visibleRows)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    row.label,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                Expanded(
                  child: Text(
                    row.value,
                    textDirection: _looksLatin(row.value)
                        ? TextDirection.ltr
                        : TextDirection.rtl,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _InfoRow {
  const _InfoRow(this.label, String? value) : value = value ?? '';

  final String label;
  final String value;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final message = error is ImdbApiException
        ? (error as ImdbApiException).message
        : error.toString();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.error),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text('جزئیاتی برای این عنوان پیدا نشد.'),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(8);
    if (url == null) {
      return _PosterFallback(radius: radius);
    }

    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        url!,
        width: 112,
        height: 164,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _PosterFallback(radius: radius),
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback({required this.radius});

  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      height: 164,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: radius,
      ),
      child: const Icon(Icons.movie_outlined, size: 36),
    );
  }
}

String _rating(double? value) {
  if (value == null) {
    return '-';
  }
  return value.toStringAsFixed(1);
}

bool _looksLatin(String value) {
  return RegExp(r'^[\x00-\x7F]+$').hasMatch(value);
}
