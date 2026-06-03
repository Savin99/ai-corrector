import pathlib
import sys
import unittest


PROJECT_DIR = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_DIR))

import corrector  # noqa: E402


class CorrectorSafetyTest(unittest.TestCase):
    def test_single_word_passthrough_preserves_form(self):
        self.assertEqual(
            corrector.single_word_passthrough("Заархивированную"),
            "Заархивированную",
        )

    def test_local_text_fixes_common_mistakes(self):
        self.assertEqual(
            corrector.local_text_fix(
                "Я прийду завтра и посмотрю, что там с коментариями."
            ),
            "Я приду завтра и посмотрю, что там с комментариями.",
        )
        self.assertEqual(
            corrector.local_text_fix("Вообщем, ихний отчёт более лучше выглядит."),
            "В общем, их отчёт лучше выглядит.",
        )

    def test_rejects_rephrased_inflections(self):
        self.assertFalse(
            corrector.correction_is_safe(
                "Разархивированными файлами пользовались вчера.",
                "Файлы разархивированы вчера.",
            )
        )

    def test_rejects_formality_shift(self):
        self.assertFalse(
            corrector.correction_is_safe(
                "Не забудь переиндексировать уже закэшированную выдачу.",
                "Не забудьте переиндексировать уже закэшированную выдачу.",
            )
        )

    def test_rejects_protected_token_changes(self):
        self.assertFalse(
            corrector.correction_is_safe(
                "В 3-м квартале команда Альфа-Банка перезапустила SSO.",
                "В третьем квартале команда Альфа-Банка перезапустила SSO.",
            )
        )
        self.assertFalse(
            corrector.correction_is_safe(
                "Не трогай feature-flag aiCorrectorBeta.",
                "Не трогай фичу-флаг `aiCorrectorBeta`.",
            )
        )

    def test_rejects_cyrillic_abbreviation_reordering(self):
        source = "то есть ты уже не через ИИ правил а через скрипт типа?"
        self.assertFalse(
            corrector.correction_is_safe(
                source,
                "То есть ты уже не через правила ИИ, а через скрипт типа?",
            )
        )
        self.assertTrue(
            corrector.correction_is_safe(
                source,
                "То есть ты уже не через ИИ правил, а через скрипт, типа?",
            )
        )

    def test_rejects_added_combining_marks(self):
        self.assertFalse(
            corrector.correction_is_safe(
                "Слушай ну я походу не туда нажал.",
                "Слушай, ну я по-хожу не ту́да нажёл.",
            )
        )

    def test_rejects_reflexive_verb_regression(self):
        self.assertFalse(
            corrector.correction_is_safe(
                "В папке лежала заархивированная копия.",
                "В папке лежалась заархивированная копия.",
            )
        )

    def test_rejects_large_word_form_rewrites(self):
        self.assertFalse(
            corrector.correction_is_safe(
                "Сверхъестественно сложно синхронизируемые настройки не применились.",
                "Сверхъестественные сложные синхронизированные настройки не применились.",
            )
        )

    def test_allows_small_spelling_fix(self):
        self.assertTrue(
            corrector.correction_is_safe(
                "Я прийду завтра с коментариями.",
                "Я приду завтра с комментариями.",
            )
        )


if __name__ == "__main__":
    unittest.main()
