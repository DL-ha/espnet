from typing import Collection

from jaconv import jaconv
import tacotron_cleaner.cleaners
from typeguard import check_argument_types
from vietnamese_cleaner import vietnamese_cleaners


class TextCleaner:
    """Text cleaner.

    Examples:
        >>> cleaner = TextCleaner("tacotron")
        >>> cleaner("(Hello-World);   &  jr. & dr.")
        'HELLO WORLD, AND JUNIOR AND DOCTOR'

    """

    def __init__(self, cleaner_types: Collection[str] = None):
        assert check_argument_types()

        if cleaner_types is None:
            self.cleaner_types = []
        elif isinstance(cleaner_types, str):
            self.cleaner_types = [cleaner_types]
        else:
            self.cleaner_types = list(cleaner_types)

    def __call__(self, text: str) -> str:
        for t in self.cleaner_types:
            if t == "tacotron":
                text = tacotron_cleaner.cleaners.custom_english_cleaners(text)
            elif t == "jaconv":
                text = jaconv.normalize(text)
            elif t == "vietnamese":
                text = vietnamese_cleaners.vietnamese_cleaner(text)
            else:
                raise RuntimeError(f"Not supported: type={t}")

        return text