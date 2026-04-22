// lib/widgets/chat_suggest_widget.dart
// Widget chatbox để nhập prompt và hiển thị mẫu gợi ý

import 'package:flutter/material.dart';
import '../services/weaving_api_service.dart';
import '../utils/app_theme.dart';

class ChatSuggestWidget extends StatelessWidget {
  final TextEditingController controller;
  final List<PatternSuggestion> suggestions;
  final bool isLoading;
  final VoidCallback onSearch;
  final ValueChanged<PatternSuggestion> onSelectPattern;

  const ChatSuggestWidget({
    super.key,
    required this.controller,
    required this.suggestions,
    required this.isLoading,
    required this.onSearch,
    required this.onSelectPattern,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppTheme.radiusLG,
        gradient: LinearGradient(
          colors: [
            AppTheme.surfaceBg.withValues(alpha: 0.95),
            AppTheme.cardBg.withValues(alpha: 0.95),
          ],
        ),
        boxShadow: AppTheme.softShadow,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  size: 18, color: AppTheme.accentBlue),
              const SizedBox(width: 6),
              const Text(
                'Tìm Mẫu Bằng Mô Tả',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Mô tả mẫu dệt bằng tiếng Việt hoặc tiếng Anh',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),

          // ── Input row ─────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onSubmitted: (_) => onSearch(),
                  decoration: InputDecoration(
                    hintText: 'VD: mẫu sọc xanh đỏ truyền thống...',
                    hintStyle: TextStyle(
                      color: AppTheme.textMuted.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: AppTheme.surfaceBg,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: AppTheme.radiusMD,
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.search,
                        size: 18, color: AppTheme.textMuted),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Nút tìm kiếm
              GestureDetector(
                onTap: isLoading ? null : onSearch,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: isLoading ? null : AppTheme.primaryGradient,
                    color: isLoading
                        ? AppTheme.textMuted.withValues(alpha: 0.3)
                        : null,
                    borderRadius: AppTheme.radiusMD,
                    boxShadow: isLoading
                        ? null
                        : AppTheme.glowShadow(AppTheme.accentBlue),
                  ),
                  child: isLoading
                      ? const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                ),
              ),
            ],
          ),

          // ── Suggestions ───────────────────────────────────────────────
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Mẫu gợi ý:',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            ...suggestions.map((s) => _buildSuggestionItem(s)),
          ],
        ],
      ),
    );
  }

  Widget _buildSuggestionItem(PatternSuggestion pattern) {
    // Điểm similarity hiển thị dạng phần trăm
    final simPercent = (pattern.similarity * 100).toStringAsFixed(0);
    final simColor = pattern.similarity > 0.7
        ? AppTheme.success
        : pattern.similarity > 0.4
            ? AppTheme.accentYellow
            : AppTheme.textMuted;

    return GestureDetector(
      onTap: () => onSelectPattern(pattern),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: AppTheme.radiusSM,
          color: AppTheme.surfaceBg,
          border: Border.all(
            color: AppTheme.lightBlue.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            // Icon mẫu
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.grid_on, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pattern.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    pattern.description,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Similarity badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: simColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: simColor.withValues(alpha: 0.3)),
              ),
              child: Text(
                '$simPercent%',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: simColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
