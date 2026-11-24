import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Page content column: centred, at most 672 px wide (like a phone column on a tablet).
class PageColumn extends StatelessWidget {
  const PageColumn({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(20, 24, 20, 24),
    this.gap = 20,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 672),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: gap), children[i]],
            ],
          ),
        ),
      ),
    );
  }
}

/// A page with the app's header: a back button on the left, the title in the middle, an action on the right.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.body,
    this.title,
    this.onBack,
    this.backLabel,
    this.action,
    this.bottom,
  });

  final String? title;
  final VoidCallback? onBack;
  final String? backLabel;
  final Widget? action;
  final Widget body;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: Material(
          color: c.surface,
          shape: Border(bottom: BorderSide(color: c.line)),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: onBack == null
                          ? null
                          : TextButton.icon(
                              onPressed: onBack,
                              icon: const Icon(Icons.chevron_left, size: 22),
                              label: Text(
                                backLabel ?? '',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                              ),
                            ),
                    ),
                  ),
                  Flexible(
                    flex: 2,
                    child: Text(
                      title ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    child: Align(alignment: Alignment.centerRight, child: action),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: body,
      bottomNavigationBar: bottom,
    );
  }
}

/// Labelled number used in summary grids.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.large = false});

  final String label;
  final String value;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: c.muted)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(fontSize: large ? 22 : 20, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// A card: surface colour, hairline border, rounded.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color, this.radius = 16});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: c.line),
      ),
      child: child,
    );
  }
}

/// A small coloured label.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.background, this.foreground});

  final String text;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: background ?? c.canvas, borderRadius: BorderRadius.circular(6)),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: foreground ?? c.inkSoft),
      ),
    );
  }
}

/// Heading used above a block of content.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
        ?trailing,
      ],
    );
  }
}

class ErrorText extends StatelessWidget {
  const ErrorText(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Text(message, style: TextStyle(fontSize: 14, color: context.colors.danger));
}

/// A text field with a label above it, like the forms of the original app.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.autofocus = false,
    this.onChanged,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final int maxLines;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          autofocus: autofocus,
          maxLines: maxLines,
          minLines: maxLines,
          onChanged: onChanged,
          keyboardType: keyboardType,
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}

/// A segmented choice: equal-width buttons, the selected one filled.
class SegmentedChoice<T> extends StatelessWidget {
  const SegmentedChoice({super.key, required this.options, required this.value, required this.onChanged, this.label});

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) ...[
          Text(label!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onChanged(options[i].$1),
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: options[i].$1 == value ? c.brand : c.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: options[i].$1 == value ? c.brand : c.lineStrong),
                    ),
                    child: Text(
                      options[i].$2,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: options[i].$1 == value ? Colors.white : c.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Shows a message at the top of the screen.
void showToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 5)));
}

/// Asks a yes/no question; true when confirmed.
Future<bool> confirmDialog(
  BuildContext context, {
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  bool destructive = false,
}) async {
  final c = context.colors;
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(cancelLabel)),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: destructive ? TextButton.styleFrom(foregroundColor: c.danger) : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// The big title at the top of a tab page.
class LargeTitle extends StatelessWidget {
  const LargeTitle(this.title, {super.key, this.subtitle, this.trailing, this.leading});

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ?leading,
              Text(
                title,
                style: const TextStyle(fontSize: 34, height: 1.15, fontWeight: FontWeight.w700, letterSpacing: -0.5),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: TextStyle(fontSize: 14, color: c.muted)),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// A round outlined icon button, like the header buttons of the original app.
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.size = 44,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: size / 2,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.surface,
            border: Border.all(color: c.lineStrong),
          ),
          child: Icon(icon, size: 20, color: onPressed == null ? c.muted : c.ink),
        ),
      ),
    );
  }
}

/// A filled call-to-action button with an optional icon.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.icon, this.height = 54});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(minimumSize: Size.fromHeight(height));
    return icon == null
        ? FilledButton(onPressed: onPressed, style: style, child: Text(label))
        : FilledButton.icon(onPressed: onPressed, style: style, icon: Icon(icon, size: 18), label: Text(label));
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({super.key, required this.label, required this.onPressed, this.icon, this.height = 54});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(minimumSize: Size.fromHeight(height));
    return icon == null
        ? OutlinedButton(onPressed: onPressed, style: style, child: Text(label))
        : OutlinedButton.icon(onPressed: onPressed, style: style, icon: Icon(icon, size: 18), label: Text(label));
  }
}

/// A bottom sheet with the app's rounded top and a safe bottom margin.
Future<T?> showAppSheet<T>(BuildContext context, {required WidgetBuilder builder, bool dismissible = true}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 672),
    builder: (context) => SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 24, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: builder(context),
    ),
  );
}

/// A row of selectable chips (single or multiple selection decided by the caller).
class ChipRow<T> extends StatelessWidget {
  const ChipRow({
    super.key,
    required this.label,
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  final String label;
  final List<(T, String)> options;
  final List<T> selected;
  final ValueChanged<T> onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (id, text) in options)
              InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => onToggle(id),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected.contains(id) ? c.ink : c.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: selected.contains(id) ? null : Border.all(color: c.lineStrong),
                  ),
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected.contains(id) ? FontWeight.w600 : FontWeight.w500,
                      color: selected.contains(id) ? c.onInk : c.ink,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// A full-screen map with a rounded sheet over its lower part (recording and tours).
class MapSheetScreen extends StatelessWidget {
  const MapSheetScreen({
    super.key,
    required this.map,
    required this.sheet,
    this.leftChip,
    this.rightChip,
    this.onCenter,
    this.centerTooltip = '',
    this.sheetFraction = 0.4,
    this.minSheetHeight = 0,
  });

  final Widget map;
  final Widget sheet;
  final Widget? leftChip;
  final Widget? rightChip;
  final VoidCallback? onCenter;
  final String centerTooltip;
  final double sheetFraction;
  final double minSheetHeight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.map,
      body: LayoutBuilder(
        builder: (context, box) {
          final sheetHeight = (box.maxHeight * sheetFraction).clamp(minSheetHeight, box.maxHeight);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 672),
              child: Stack(
                children: [
                  Positioned(left: 0, right: 0, top: 0, bottom: sheetHeight - 24, child: map),
                  Positioned(
                    left: 16,
                    right: 16,
                    top: MediaQuery.of(context).padding.top + 16,
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [?leftChip, ?rightChip]),
                  ),
                  if (onCenter != null)
                    Positioned(
                      right: 16,
                      bottom: sheetHeight + 16,
                      child: Tooltip(
                        message: centerTooltip,
                        child: Material(
                          color: c.surface,
                          elevation: 3,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: onCenter,
                            child: const SizedBox(width: 48, height: 48, child: Icon(Icons.my_location, size: 22)),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: sheetHeight,
                    child: Material(
                      color: c.surface,
                      elevation: 8,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 12, bottom: 8),
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(color: c.lineStrong, borderRadius: BorderRadius.circular(2)),
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).padding.bottom),
                              child: sheet,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A floating pill on a map: a label with an optional leading dot or icon.
class MapChip extends StatelessWidget {
  const MapChip({super.key, required this.label, this.onTap, this.leading});

  final String label;
  final VoidCallback? onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      elevation: 3,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 8)],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small coloured status dot.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 10});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// A label over a value, for the numbers of a recording or a tour.
class Metric extends StatelessWidget {
  const Metric({super.key, required this.label, required this.value, this.sub});

  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: c.muted)),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        if (sub != null)
          Text(
            sub!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
      ],
    );
  }
}

/// A bottom drawer with a handle: tap it or drag down to hide [child], up to show it again.
/// Whether it is collapsed is owned by the parent.
class CollapsibleSheet extends StatelessWidget {
  const CollapsibleSheet({
    super.key,
    required this.collapsed,
    required this.onCollapsedChange,
    required this.handleLabel,
    required this.summary,
    required this.child,
    this.maxHeightFraction = 0.6,
  });

  final bool collapsed;
  final ValueChanged<bool> onCollapsedChange;

  /// Accessible name of the handle, describing what activating it does.
  final String handleLabel;

  /// Always visible, right under the handle.
  final Widget summary;

  /// Hidden when collapsed.
  final Widget child;
  final double maxHeightFraction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final maxHeight = MediaQuery.of(context).size.height * maxHeightFraction;
    return Material(
      color: c.surface,
      elevation: 8,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                button: true,
                label: handleLabel,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onCollapsedChange(!collapsed),
                  onVerticalDragEnd: (details) {
                    final v = details.primaryVelocity ?? 0;
                    if (v > 80) onCollapsedChange(true);
                    if (v < -80) onCollapsedChange(false);
                  },
                  child: SizedBox(
                    height: 28,
                    width: double.infinity,
                    child: Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(color: c.lineStrong, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: summary),
              Flexible(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  alignment: Alignment.topCenter,
                  child: collapsed
                      ? const SizedBox(width: double.infinity)
                      : SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 16), child: child),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small action button.
class SmallButton extends StatelessWidget {
  const SmallButton({super.key, required this.label, required this.onPressed, this.primary = false});

  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final shape = WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
    const size = WidgetStatePropertyAll(Size(0, 44));
    final text = Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600));
    return primary
        ? FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom().copyWith(minimumSize: size, shape: shape),
            child: text,
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom().copyWith(minimumSize: size, shape: shape),
            child: text,
          );
  }
}
