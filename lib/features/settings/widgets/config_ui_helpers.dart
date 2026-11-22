import 'package:download_manager/core/localization/app_strings.dart';
import 'package:download_manager/core/theme/app_colors.dart';
import 'package:material_ui/material_ui.dart';

class ConfigUi {
  static Widget tabHeader(IconData icon, String title, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 28, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppStrings.instance.t(title),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 10),
                      trailing,
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Container(height: 1, color: const Color(0xFF3E3E3E)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget checkRow({
    required bool value,
    required String label,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: Checkbox(
              value: value,
              activeColor: enabled ? AppColors.accent : const Color(0xFF555555),
              checkColor: Colors.black,
              side: BorderSide(
                color: enabled
                    ? const Color(0xFF6B6B6B)
                    : const Color(0xFF424242),
              ),
              onChanged: enabled ? (v) => onChanged(v ?? false) : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: enabled ? () => onChanged(!value) : null,
              child: Text(
                AppStrings.instance.t(label),
                style: TextStyle(
                  color: enabled
                      ? const Color(0xFFE5E5E5)
                      : const Color(0xFF777777),
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget radioRow<T>({
    required T value,
    required T groupValue,
    required String label,
    required ValueChanged<T> onChanged,
  }) {
    final selected = value == groupValue;
    return InkWell(
      onTap: () => onChanged(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.accent : const Color(0xFF777777),
                  width: 1.5,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.accent,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppStrings.instance.t(label),
                style: const TextStyle(color: Color(0xFFE5E5E5), fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget groupBox({
    required String title,
    required Widget child,
    EdgeInsets padding = const EdgeInsets.fromLTRB(10, 12, 10, 10),
  }) {
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(top: 7),
          padding: padding,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF3E3E3E)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: child,
        ),
        Positioned(
          left: 8,
          top: 0,
          child: Container(
            color: const Color(0xFF282828),
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Text(
              AppStrings.instance.t(title),
              style: const TextStyle(
                color: Color(0xFFD8D8D8),
                fontSize: 11.5,
              ),
            ),
          ),
        ),
      ],
    );
  }

  static Widget textField({
    required TextEditingController controller,
    bool enabled = true,
    bool obscure = false,
    int maxLines = 1,
    TextAlign textAlign = TextAlign.start,
    String? hint,
    ValueChanged<String>? onChanged,
  }) {
    return SizedBox(
      height: maxLines == 1 ? 26 : null,
      child: TextField(
        controller: controller,
        enabled: enabled,
        obscureText: obscure,
        maxLines: maxLines,
        textAlign: textAlign,
        onChanged: onChanged,
        style: TextStyle(
          color: enabled ? Colors.white : const Color(0xFF777777),
          fontSize: 12,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF707070), fontSize: 11.5),
          filled: true,
          fillColor: enabled
              ? const Color(0xFF1A1A1A)
              : const Color(0xFF202020),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 6,
          ),
          disabledBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
            borderSide: BorderSide(color: Color(0xFF333333)),
          ),
          enabledBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
            borderSide: BorderSide(color: Color(0xFF454545)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
            borderSide: BorderSide(color: AppColors.accent, width: 1.2),
          ),
        ),
      ),
    );
  }

  static Widget dropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String> onChanged,
    bool enabled = true,
  }) {
    final safeValue = items.contains(value) ? value : items.first;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: enabled ? const Color(0xFF1D1D1D) : const Color(0xFF222222),
        border: Border.all(
          color: enabled ? const Color(0xFF454545) : const Color(0xFF343434),
        ),
        borderRadius: BorderRadius.circular(2),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          isExpanded: true,
          dropdownColor: const Color(0xFF252525),
          iconEnabledColor: const Color(0xFFC0C0C0),
          iconDisabledColor: const Color(0xFF555555),
          style: TextStyle(
            color: enabled ? Colors.white : const Color(0xFF777777),
            fontSize: 12,
          ),
          items: items
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item,
                  child: Text(
                    item,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: enabled
              ? (v) {
                  if (v != null) onChanged(v);
                }
              : null,
        ),
      ),
    );
  }

  static Widget button(
    String label, {
    VoidCallback? onPressed,
    bool primary = false,
    double? width,
  }) {
    final enabled = onPressed != null;
    return SizedBox(
      width: width,
      height: 26,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: enabled
              ? (primary ? const Color(0xFF243B31) : const Color(0xFF323232))
              : const Color(0xFF262626),
          foregroundColor: enabled ? Colors.white : const Color(0xFF707070),
          side: BorderSide(
            color: enabled
                ? (primary ? AppColors.accent : const Color(0xFF4E4E4E))
                : const Color(0xFF393939),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
          textStyle: const TextStyle(fontSize: 12),
        ),
        child: Text(
          AppStrings.instance.t(label),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  static Widget spinner({
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
    bool enabled = true,
    double width = 92,
  }) {
    return Container(
      width: width,
      height: 26,
      decoration: BoxDecoration(
        color: enabled ? const Color(0xFF1A1A1A) : const Color(0xFF212121),
        border: Border.all(
          color: enabled ? const Color(0xFF454545) : const Color(0xFF343434),
        ),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '$value',
                style: TextStyle(
                  color: enabled ? Colors.white : const Color(0xFF707070),
                  fontSize: 12,
                ),
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              InkWell(
                onTap: (enabled && value < max) ? () => onChanged(value + 1) : null,
                child: const Icon(
                  Icons.arrow_drop_up,
                  size: 12,
                  color: Color(0xFFC0C0C0),
                ),
              ),
              InkWell(
                onTap: (enabled && value > min) ? () => onChanged(value - 1) : null,
                child: const Icon(
                  Icons.arrow_drop_down,
                  size: 12,
                  color: Color(0xFFC0C0C0),
                ),
              ),
            ],
          ),
          const SizedBox(width: 2),
        ],
      ),
    );
  }
}
