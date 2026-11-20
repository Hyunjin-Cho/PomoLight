#!/usr/bin/env python3
"""Assemble Resources/<lang>.lproj/Localizable.strings from the localization
workflow's JSON output. Missing keys fall back to the English source so nothing
is ever blank. Usage: python3 Scripts/assemble_localizations.py <workflow_output.json>"""
import json, os, sys

out_path = sys.argv[1]
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
res_dir = os.path.join(root, "Resources")

with open(out_path, "r", encoding="utf-8") as f:
    data = json.load(f)

result = data["result"]
keys = result["keys"]
by_lang = result["byLang"]

# Keys the old workflow JSON still carries but the app never looks up. They are
# dropped here so a re-assembly can't resurrect them (2026-08-15):
#   "Custom color" — the custom accent-color feature was removed in PR #2.
#   "Soft Chime"   — alarm-sound names are drawn with Text(verbatim:) in
#                    SettingsPanelView, so they never go through this table.
# Also gone in the same pass: the hardcoded "Glass"/"Submarine" system-sound
# names, which were never even values of AlarmSound. If sound names are ever
# localized, take "Soft Chime" back out of this set.
#   "Notifications off" (2026-08-21) — the widget's bell-slash badge. The widget
#                    went in PR #33; grep finds no lookup in Sources/, yet the
#                    string was still sitting in all 29 .lproj files and in the
#                    MANUAL table below, ready to be written back on the next
#                    re-assembly. Removed from the files in the same commit.
#   "Donate", "Support PomoLight with a donation", "Support PomoLight"
#                    (2026-11-19, #6) — the owner dropped donations; the heart and
#                    the Settings footer line went, replaced by the developer's
#                    GitHub address, which is drawn verbatim and needs no table.
#                    Removed from all 29 .lproj files in the same commit.
SKIP_KEYS = {"Custom color", "Soft Chime", "Notifications off",
             "Donate", "Support PomoLight with a donation", "Support PomoLight"}

# Keys added AFTER the original workflow ran, hand-translated (2026-07: the
# VoiceOver remaining-time phrase). Merged so re-assembling from the old workflow
# JSON never drops them. A future workflow that includes these keys wins over
# this table. 2026-08-21: the widget's "Notifications off" badge was dropped from
# here — see SKIP_KEYS above.
MANUAL = {
    # 2026-11-20 (#53): the Remove PomoLight… flow, and (#70 F-8) names for the Custom ± buttons.
    # Written from the Korean originals; "Move to Trash", "Show in Finder", "Cancel", "OK" and the
    # "System Settings ▸ Notifications" path follow each language's own macOS wording. macOS has no
    # Filipino localization, so fil keeps the English names its users see on screen.
    "Remove PomoLight…": {
        "cs": "Odstranit PomoLight…", "da": "Fjern PomoLight…", "de": "PomoLight entfernen …",
        "el": "Αφαίρεση του PomoLight…", "es": "Eliminar PomoLight…", "fi": "Poista PomoLight…",
        "fil": "Alisin ang PomoLight…", "fr": "Supprimer PomoLight…", "hu": "PomoLight eltávolítása…",
        "id": "Hapus PomoLight…", "it": "Rimuovi PomoLight…", "ja": "PomoLightを削除…", "ko": "PomoLight 삭제…",
        "ms": "Buang PomoLight…", "nb": "Fjern PomoLight…", "nl": "PomoLight verwijderen…",
        "pl": "Usuń PomoLight…", "pt-BR": "Remover o PomoLight…", "pt-PT": "Remover o PomoLight…",
        "ro": "Elimină PomoLight…", "ru": "Удалить PomoLight…", "sv": "Ta bort PomoLight…",
        "th": "ลบ PomoLight…", "tr": "PomoLight'ı Kaldır…", "uk": "Видалити PomoLight…",
        "vi": "Xóa PomoLight…", "zh-Hans": "移除 PomoLight…", "zh-Hant": "移除 PomoLight…",
    },
    "Moves PomoLight to the Trash and deletes what it saved.": {
        "cs": "Přesune PomoLight do koše a smaže, co uložil.",
        "da": "Flytter PomoLight til papirkurven og sletter det, appen har gemt.",
        "de": "Legt PomoLight in den Papierkorb und löscht, was es gespeichert hat.",
        "el": "Μεταφέρει το PomoLight στον Κάδο και διαγράφει ό,τι έχει αποθηκεύσει.",
        "es": "Traslada PomoLight a la papelera y borra lo que guardó.",
        "fi": "Siirtää PomoLightin roskakoriin ja poistaa sen tallentamat tiedot.",
        "fil": "Inililipat ang PomoLight sa Trash at binubura ang mga na-save nito.",
        "fr": "Place PomoLight dans la corbeille et efface ce qu'il a enregistré.",
        "hu": "Áthelyezi a PomoLightot a Kukába, és törli, amit elmentett.",
        "id": "Memindahkan PomoLight ke Tong Sampah dan menghapus yang disimpannya.",
        "it": "Sposta PomoLight nel Cestino ed elimina ciò che ha salvato.",
        "ja": "PomoLightをゴミ箱に入れ、保存した設定を消去します。", "ko": "PomoLight를 휴지통으로 옮기고, 저장해 둔 설정을 지워요.",
        "ms": "Mengalihkan PomoLight ke Tong Sampah dan memadam apa yang disimpannya.",
        "nb": "Flytter PomoLight til papirkurven og sletter det som er lagret.",
        "nl": "Verplaatst PomoLight naar de prullenmand en wist wat het heeft bewaard.",
        "pl": "Przenosi PomoLight do kosza i usuwa zapisane przez niego dane.",
        "pt-BR": "Move o PomoLight para o Lixo e apaga o que ele salvou.",
        "pt-PT": "Move o PomoLight para o Lixo e apaga o que guardou.",
        "ro": "Mută PomoLight la Coș și șterge ce a salvat.",
        "ru": "Перемещает PomoLight в Корзину и удаляет сохранённые им данные.",
        "sv": "Flyttar PomoLight till papperskorgen och raderar det som har sparats.",
        "th": "ย้าย PomoLight ไปถังขยะและลบข้อมูลที่บันทึกไว้",
        "tr": "PomoLight'ı Çöp Sepeti'ne taşır ve kaydettiklerini siler.",
        "uk": "Переміщує PomoLight у Смітник і видаляє збережені ним дані.",
        "vi": "Chuyển PomoLight vào Thùng rác và xóa những gì ứng dụng đã lưu.",
        "zh-Hans": "将 PomoLight 移到废纸篓，并删除它保存的设置。", "zh-Hant": "將 PomoLight 丟到垃圾桶，並刪除它儲存的設定。",
    },
    "Remove PomoLight?": {
        "cs": "Odstranit PomoLight?", "da": "Fjern PomoLight?", "de": "PomoLight entfernen?",
        "el": "Αφαίρεση του PomoLight;", "es": "¿Eliminar PomoLight?", "fi": "Poistetaanko PomoLight?",
        "fil": "Alisin ang PomoLight?", "fr": "Supprimer PomoLight ?", "hu": "Eltávolítja a PomoLightot?",
        "id": "Hapus PomoLight?", "it": "Rimuovere PomoLight?", "ja": "PomoLightを削除しますか？",
        "ko": "PomoLight를 삭제할까요?", "ms": "Buang PomoLight?", "nb": "Fjerne PomoLight?",
        "nl": "PomoLight verwijderen?", "pl": "Usunąć PomoLight?", "pt-BR": "Remover o PomoLight?",
        "pt-PT": "Remover o PomoLight?", "ro": "Elimini PomoLight?", "ru": "Удалить PomoLight?",
        "sv": "Ta bort PomoLight?", "th": "ลบ PomoLight หรือไม่", "tr": "PomoLight kaldırılsın mı?",
        "uk": "Видалити PomoLight?", "vi": "Xóa PomoLight?", "zh-Hans": "要移除 PomoLight 吗？",
        "zh-Hant": "要移除 PomoLight 嗎？",
    },
    "PomoLight will be moved to the Trash, so you can put it back from there if you change your mind.": {
        "cs": "PomoLight bude přesunut do koše, takže ho odtamtud můžete vrátit, pokud si to rozmyslíte.",
        "da": "PomoLight flyttes til papirkurven, så du kan lægge det tilbage derfra, hvis du fortryder.",
        "de": "PomoLight wird in den Papierkorb gelegt – wenn du es dir anders überlegst, kannst du es von dort zurücklegen.",
        "el": "Το PomoLight θα μεταφερθεί στον Κάδο, οπότε μπορείτε να το επαναφέρετε από εκεί αν αλλάξετε γνώμη.",
        "es": "PomoLight se trasladará a la papelera, así que podrás recuperarlo desde allí si cambias de opinión.",
        "fi": "PomoLight siirretään roskakoriin, joten voit palauttaa sen sieltä, jos muutat mielesi.",
        "fil": "Ililipat ang PomoLight sa Trash, kaya maibabalik mo ito mula roon kung magbago ang isip mo.",
        "fr": "PomoLight sera placé dans la corbeille : si vous changez d'avis, vous pourrez l'y récupérer.",
        "hu": "A PomoLight a Kukába kerül, így onnan visszateheti, ha meggondolja magát.",
        "id": "PomoLight akan dipindahkan ke Tong Sampah, jadi Anda bisa mengembalikannya dari sana jika berubah pikiran.",
        "it": "PomoLight verrà spostato nel Cestino, quindi potrai ripristinarlo da lì se cambi idea.",
        "ja": "PomoLightはゴミ箱に移動します。気が変わったら、ゴミ箱から戻せます。",
        "ko": "PomoLight는 휴지통으로 옮겨져요. 마음이 바뀌면 휴지통에서 되돌릴 수 있어요.",
        "ms": "PomoLight akan dialihkan ke Tong Sampah, jadi anda boleh mengembalikannya dari sana jika berubah fikiran.",
        "nb": "PomoLight flyttes til papirkurven, så du kan legge det tilbake derfra hvis du ombestemmer deg.",
        "nl": "PomoLight wordt naar de prullenmand verplaatst, dus je kunt het daar terugzetten als je van gedachten verandert.",
        "pl": "PomoLight zostanie przeniesiony do kosza, więc jeśli zmienisz zdanie, możesz go stamtąd przywrócić.",
        "pt-BR": "O PomoLight será movido para o Lixo, então dá para recuperá-lo de lá se mudar de ideia.",
        "pt-PT": "O PomoLight será movido para o Lixo, por isso podes recuperá-lo de lá se mudares de ideias.",
        "ro": "PomoLight va fi mutat la Coș, așa că îl poți recupera de acolo dacă te răzgândești.",
        "ru": "PomoLight будет перемещён в Корзину — если передумаете, его можно вернуть оттуда.",
        "sv": "PomoLight flyttas till papperskorgen, så du kan lägga tillbaka det därifrån om du ångrar dig.",
        "th": "PomoLight จะถูกย้ายไปถังขยะ หากเปลี่ยนใจก็นำกลับมาจากถังขยะได้",
        "tr": "PomoLight Çöp Sepeti'ne taşınır; fikrinizi değiştirirseniz oradan geri alabilirsiniz.",
        "uk": "PomoLight буде переміщено в Смітник — якщо передумаєте, його можна повернути звідти.",
        "vi": "PomoLight sẽ được chuyển vào Thùng rác, nên nếu đổi ý bạn có thể lấy lại từ đó.",
        "zh-Hans": "PomoLight 将被移到废纸篓。如果改变主意，可以从废纸篓放回。", "zh-Hant": "PomoLight 會被移到垃圾桶。如果改變主意，可以從垃圾桶放回。",
    },
    "Your themes, sounds and durations will be deleted.": {
        "cs": "Vaše motivy, zvuky a délky budou smazány.", "da": "Dine temaer, lyde og tider slettes.",
        "de": "Deine Designfarben, Töne und Zeiten werden gelöscht.",
        "el": "Τα θέματα, οι ήχοι και οι διάρκειές σας θα διαγραφούν.",
        "es": "Se borrarán tus temas, sonidos y duraciones.", "fi": "Teemasi, äänesi ja ajat poistetaan.",
        "fil": "Mabubura ang iyong mga tema, tunog at tagal.",
        "fr": "Vos thèmes, sons et durées seront effacés.",
        "hu": "A témák, hangok és időtartamok törlődnek.",
        "id": "Tema, suara, dan durasi Anda akan dihapus.",
        "it": "I tuoi temi, suoni e durate verranno eliminati.", "ja": "テーマ、アラーム音、時間の設定は消去されます。",
        "ko": "테마, 알림음, 시간 설정은 지워져요.", "ms": "Tema, bunyi dan tempoh anda akan dipadam.",
        "nb": "Temaene, lydene og tidene dine slettes.",
        "nl": "Je thema's, geluiden en tijden worden gewist.",
        "pl": "Twoje motywy, dźwięki i czasy zostaną usunięte.",
        "pt-BR": "Seus temas, sons e durações serão apagados.",
        "pt-PT": "Os teus temas, sons e durações serão apagados.",
        "ro": "Temele, sunetele și duratele tale vor fi șterse.",
        "ru": "Ваши темы, звуки и длительности будут удалены.", "sv": "Dina teman, ljud och tider raderas.",
        "th": "ธีม เสียง และระยะเวลาที่ตั้งไว้จะถูกลบ",
        "tr": "Temalarınız, sesleriniz ve süreleriniz silinecek.",
        "uk": "Ваші теми, звуки й тривалості буде видалено.",
        "vi": "Chủ đề, âm thanh và thời lượng của bạn sẽ bị xóa.", "zh-Hans": "主题、提示音和时长设置将被删除。",
        "zh-Hant": "主題、提示音和時間長度設定將被刪除。",
    },
    "%d files it saved will be removed.": {
        "cs": "Uložené soubory budou odstraněny (%d).", "da": "%d gemte filer fjernes.",
        "de": "%d gespeicherte Dateien werden entfernt.", "el": "Θα αφαιρεθούν %d αποθηκευμένα αρχεία.",
        "es": "Se eliminarán %d archivos que guardó.", "fi": "%d tallennettua tiedostoa poistetaan.",
        "fil": "Aalisin ang %d file na na-save nito.", "fr": "%d fichiers enregistrés seront supprimés.",
        "hu": "%d mentett fájl törlődik.", "id": "%d file yang disimpan akan dihapus.",
        "it": "Verranno rimossi %d file salvati.", "ja": "PomoLightが保存したファイル%d個を削除します。",
        "ko": "PomoLight가 저장한 파일 %d개를 지워요.", "ms": "%d fail yang disimpan akan dibuang.",
        "nb": "%d lagrede filer fjernes.", "nl": "%d bewaarde bestanden worden verwijderd.",
        "pl": "Zapisane pliki zostaną usunięte (%d).", "pt-BR": "%d arquivos salvos serão removidos.",
        "pt-PT": "Serão removidos %d ficheiros guardados.", "ro": "Fișierele salvate vor fi eliminate (%d).",
        "ru": "Сохранённые файлы будут удалены (%d).", "sv": "%d sparade filer tas bort.",
        "th": "ไฟล์ที่บันทึกไว้ %d ไฟล์จะถูกลบ", "tr": "Kaydedilen %d dosya kaldırılacak.",
        "uk": "Збережені файли буде видалено (%d).", "vi": "%d tệp đã lưu sẽ bị xóa.",
        "zh-Hans": "将删除 PomoLight 保存的 %d 个文件。", "zh-Hant": "將刪除 PomoLight 儲存的 %d 個檔案。",
    },
    "Its entry in System Settings ▸ Notifications belongs to macOS and stays until macOS drops it.": {
        "cs": "Jeho položka v Nastavení systému ▸ Oznámení patří macOS a zůstane, dokud ji macOS neodstraní.",
        "da": "Dens punkt i Systemindstillinger ▸ Notifikationer tilhører macOS og bliver, indtil macOS fjerner det.",
        "de": "Der Eintrag unter Systemeinstellungen ▸ Mitteilungen gehört zu macOS und bleibt, bis macOS ihn entfernt.",
        "el": "Η καταχώρισή του στις Ρυθμίσεις συστήματος ▸ Γνωστοποιήσεις ανήκει στο macOS και παραμένει μέχρι να την αφαιρέσει το macOS.",
        "es": "Su entrada en Ajustes del Sistema ▸ Notificaciones pertenece a macOS y permanece hasta que macOS la elimine.",
        "fi": "Sen kohta Järjestelmäasetukset ▸ Ilmoitukset kuuluu macOS:lle ja säilyy, kunnes macOS poistaa sen.",
        "fil": "Ang entry nito sa System Settings ▸ Notifications ay pag-aari ng macOS at mananatili hanggang alisin ito ng macOS.",
        "fr": "Son entrée dans Réglages Système ▸ Notifications appartient à macOS et y reste jusqu'à ce que macOS la retire.",
        "hu": "A Rendszerbeállítások ▸ Értesítések alatti bejegyzése a macOS-hez tartozik, és addig marad, amíg a macOS el nem távolítja.",
        "id": "Entrinya di Pengaturan Sistem ▸ Pemberitahuan milik macOS dan tetap ada sampai macOS menghapusnya.",
        "it": "La sua voce in Impostazioni di Sistema ▸ Notifiche appartiene a macOS e resta finché macOS non la rimuove.",
        "ja": "システム設定 ▸ 通知にあるPomoLightの項目はmacOSが管理しているため、macOSが整理するまで残ります。",
        "ko": "시스템 설정 ▸ 알림에 있는 PomoLight 항목은 macOS가 관리해서, macOS가 정리할 때까지 남아 있어요.",
        "ms": "Entrinya dalam Seting Sistem ▸ Pemberitahuan milik macOS dan kekal sehingga macOS membuangnya.",
        "nb": "Oppføringen i Systeminnstillinger ▸ Varslinger tilhører macOS og blir værende til macOS fjerner den.",
        "nl": "Het onderdeel in Systeeminstellingen ▸ Berichtgeving hoort bij macOS en blijft staan tot macOS het verwijdert.",
        "pl": "Jego pozycja w Ustawieniach systemowych ▸ Powiadomienia należy do macOS i pozostanie tam, dopóki macOS jej nie usunie.",
        "pt-BR": "O item dele em Ajustes do Sistema ▸ Notificações pertence ao macOS e continua lá até o macOS removê-lo.",
        "pt-PT": "A entrada em Definições do Sistema ▸ Notificações pertence ao macOS e fica lá até o macOS a remover.",
        "ro": "Intrarea sa din Configurări sistem ▸ Notificări aparține macOS și rămâne până când macOS o elimină.",
        "ru": "Его пункт в разделе «Системные настройки ▸ Уведомления» принадлежит macOS и останется, пока macOS его не уберёт.",
        "sv": "Dess post i Systeminställningar ▸ Notiser tillhör macOS och finns kvar tills macOS tar bort den.",
        "th": "รายการของ PomoLight ใน การตั้งค่าระบบ ▸ การแจ้งเตือน เป็นของ macOS และจะยังอยู่จนกว่า macOS จะลบออก",
        "tr": "Sistem Ayarları ▸ Bildirimler'deki kaydı macOS'e aittir ve macOS onu kaldırana kadar orada kalır.",
        "uk": "Його пункт у розділі «Системні параметри ▸ Сповіщення» належить macOS і залишиться, доки macOS його не прибере.",
        "vi": "Mục của ứng dụng trong Cài đặt hệ thống ▸ Thông báo thuộc về macOS và sẽ còn đó cho đến khi macOS xóa nó.",
        "zh-Hans": "“系统设置 ▸ 通知”中的 PomoLight 项目由 macOS 管理，会一直保留到 macOS 将其清除。",
        "zh-Hant": "「系統設定 ▸ 通知」中的 PomoLight 項目由 macOS 管理，會保留到 macOS 將其清除為止。",
    },
    "Move to Trash": {
        "cs": "Přesunout do koše", "da": "Flyt til papirkurven", "de": "In den Papierkorb legen",
        "el": "Μεταφορά στον Κάδο", "es": "Trasladar a la papelera", "fi": "Siirrä roskakoriin",
        "fil": "Ilipat sa Trash", "fr": "Placer dans la corbeille", "hu": "Áthelyezés a Kukába",
        "id": "Pindahkan ke Tong Sampah", "it": "Sposta nel Cestino", "ja": "ゴミ箱に入れる", "ko": "휴지통으로 이동",
        "ms": "Alih ke Tong Sampah", "nb": "Flytt til papirkurven", "nl": "Verplaats naar prullenmand",
        "pl": "Przenieś do kosza", "pt-BR": "Mover para o Lixo", "pt-PT": "Mover para o Lixo",
        "ro": "Mută la Coș", "ru": "Переместить в Корзину", "sv": "Flytta till papperskorgen",
        "th": "ย้ายไปถังขยะ", "tr": "Çöp Sepetine Taşı", "uk": "Перемістити в Смітник",
        "vi": "Chuyển vào Thùng rác", "zh-Hans": "移到废纸篓", "zh-Hant": "丟到垃圾桶",
    },
    "Cancel": {
        "cs": "Zrušit", "da": "Annuller", "de": "Abbrechen", "el": "Ακύρωση", "es": "Cancelar",
        "fi": "Kumoa", "fil": "Kanselahin", "fr": "Annuler", "hu": "Mégsem", "id": "Batalkan",
        "it": "Annulla", "ja": "キャンセル", "ko": "취소", "ms": "Batal", "nb": "Avbryt", "nl": "Annuleer",
        "pl": "Anuluj", "pt-BR": "Cancelar", "pt-PT": "Cancelar", "ro": "Anulează", "ru": "Отменить",
        "sv": "Avbryt", "th": "ยกเลิก", "tr": "Vazgeç", "uk": "Скасувати", "vi": "Hủy", "zh-Hans": "取消",
        "zh-Hant": "取消",
    },
    "PomoLight could not be moved to the Trash": {
        "cs": "PomoLight se nepodařilo přesunout do koše",
        "da": "PomoLight kunne ikke flyttes til papirkurven",
        "de": "PomoLight konnte nicht in den Papierkorb gelegt werden",
        "el": "Δεν ήταν δυνατή η μεταφορά του PomoLight στον Κάδο",
        "es": "No se pudo trasladar PomoLight a la papelera",
        "fi": "PomoLightia ei voitu siirtää roskakoriin", "fil": "Hindi mailipat ang PomoLight sa Trash",
        "fr": "Impossible de placer PomoLight dans la corbeille",
        "hu": "A PomoLightot nem sikerült a Kukába helyezni",
        "id": "PomoLight tidak dapat dipindahkan ke Tong Sampah",
        "it": "Impossibile spostare PomoLight nel Cestino", "ja": "PomoLightをゴミ箱に移動できませんでした",
        "ko": "PomoLight를 휴지통으로 옮기지 못했어요", "ms": "PomoLight tidak dapat dialihkan ke Tong Sampah",
        "nb": "Kunne ikke flytte PomoLight til papirkurven",
        "nl": "PomoLight kon niet naar de prullenmand worden verplaatst",
        "pl": "Nie udało się przenieść PomoLight do kosza",
        "pt-BR": "Não foi possível mover o PomoLight para o Lixo",
        "pt-PT": "Não foi possível mover o PomoLight para o Lixo",
        "ro": "PomoLight nu a putut fi mutat la Coș", "ru": "Не удалось переместить PomoLight в Корзину",
        "sv": "PomoLight kunde inte flyttas till papperskorgen", "th": "ไม่สามารถย้าย PomoLight ไปถังขยะได้",
        "tr": "PomoLight Çöp Sepeti'ne taşınamadı", "uk": "Не вдалося перемістити PomoLight у Смітник",
        "vi": "Không thể chuyển PomoLight vào Thùng rác", "zh-Hans": "无法将 PomoLight 移到废纸篓",
        "zh-Hant": "無法將 PomoLight 移到垃圾桶",
    },
    "Nothing was removed. You can move it yourself:": {
        "cs": "Nic nebylo odstraněno. Můžete ho přesunout sami:",
        "da": "Intet blev fjernet. Du kan selv flytte det:",
        "de": "Es wurde nichts entfernt. Du kannst es selbst verschieben:",
        "el": "Δεν αφαιρέθηκε τίποτα. Μπορείτε να το μετακινήσετε μόνοι σας:",
        "es": "No se eliminó nada. Puedes moverlo tú mismo:",
        "fi": "Mitään ei poistettu. Voit siirtää sen itse:",
        "fil": "Walang inalis. Maaari mo itong ilipat nang mano-mano:",
        "fr": "Rien n'a été supprimé. Vous pouvez le déplacer vous-même :",
        "hu": "Semmi sem lett eltávolítva. Saját kezűleg is áthelyezheti:",
        "id": "Tidak ada yang dihapus. Anda bisa memindahkannya sendiri:",
        "it": "Non è stato rimosso nulla. Puoi spostarlo tu:", "ja": "何も削除していません。次の場所から自分で移動できます：",
        "ko": "아무것도 지우지 않았어요. 아래 위치에서 직접 옮길 수 있어요:",
        "ms": "Tiada apa-apa yang dibuang. Anda boleh mengalihkannya sendiri:",
        "nb": "Ingenting ble fjernet. Du kan flytte det selv:",
        "nl": "Er is niets verwijderd. Je kunt het zelf verplaatsen:",
        "pl": "Nic nie zostało usunięte. Możesz przenieść go samodzielnie:",
        "pt-BR": "Nada foi removido. Você pode movê-lo manualmente:",
        "pt-PT": "Nada foi removido. Podes movê-lo tu próprio:",
        "ro": "Nu s-a eliminat nimic. Îl poți muta singur:",
        "ru": "Ничего не удалено. Можно переместить его вручную:",
        "sv": "Ingenting togs bort. Du kan flytta det själv:", "th": "ยังไม่มีอะไรถูกลบ คุณย้ายเองได้ที่:",
        "tr": "Hiçbir şey kaldırılmadı. Kendiniz taşıyabilirsiniz:",
        "uk": "Нічого не видалено. Можна перемістити його вручну:",
        "vi": "Chưa có gì bị xóa. Bạn có thể tự di chuyển ứng dụng:", "zh-Hans": "没有删除任何内容。你可以自己移动它：",
        "zh-Hant": "沒有刪除任何項目。你可以自行移動它：",
    },
    "Show in Finder": {
        "cs": "Zobrazit ve Finderu", "da": "Vis i Finder", "de": "Im Finder zeigen",
        "el": "Εμφάνιση στο Finder", "es": "Mostrar en Finder", "fi": "Näytä Finderissa",
        "fil": "Ipakita sa Finder", "fr": "Afficher dans le Finder", "hu": "Megjelenítés a Finderben",
        "id": "Tampilkan di Finder", "it": "Mostra nel Finder", "ja": "Finderで表示", "ko": "Finder에서 보기",
        "ms": "Tunjukkan dalam Finder", "nb": "Vis i Finder", "nl": "Toon in Finder",
        "pl": "Pokaż w Finderze", "pt-BR": "Mostrar no Finder", "pt-PT": "Mostrar no Finder",
        "ro": "Afișează în Finder", "ru": "Показать в Finder", "sv": "Visa i Finder", "th": "แสดงใน Finder",
        "tr": "Finder'da Göster", "uk": "Показати у Finder", "vi": "Hiển thị trong Finder",
        "zh-Hans": "在访达中显示", "zh-Hant": "在 Finder 中顯示",
    },
    "OK": {
        "cs": "OK", "da": "OK", "de": "OK", "el": "OK", "es": "Aceptar", "fi": "OK", "fil": "OK", "fr": "OK",
        "hu": "OK", "id": "OK", "it": "OK", "ja": "OK", "ko": "확인", "ms": "OK", "nb": "OK", "nl": "OK",
        "pl": "OK", "pt-BR": "OK", "pt-PT": "OK", "ro": "OK", "ru": "OK", "sv": "OK", "th": "ตกลง",
        "tr": "Tamam", "uk": "OK", "vi": "OK", "zh-Hans": "好", "zh-Hant": "好",
    },
    "One minute less": {
        "cs": "O minutu méně", "da": "Ét minut mindre", "de": "Eine Minute weniger",
        "el": "Ένα λεπτό λιγότερο", "es": "Un minuto menos", "fi": "Minuutti vähemmän",
        "fil": "Bawasan ng 1 minuto", "fr": "Une minute de moins", "hu": "Egy perccel kevesebb",
        "id": "Kurangi 1 menit", "it": "Un minuto in meno", "ja": "1分減らす", "ko": "1분 줄이기",
        "ms": "Kurang 1 minit", "nb": "Ett minutt mindre", "nl": "Eén minuut minder", "pl": "Minuta mniej",
        "pt-BR": "Um minuto a menos", "pt-PT": "Menos um minuto", "ro": "Cu un minut mai puțin",
        "ru": "На минуту меньше", "sv": "En minut mindre", "th": "ลด 1 นาที", "tr": "Bir dakika az",
        "uk": "На хвилину менше", "vi": "Bớt 1 phút", "zh-Hans": "减少 1 分钟", "zh-Hant": "減少 1 分鐘",
    },
    "One minute more": {
        "cs": "O minutu více", "da": "Ét minut mere", "de": "Eine Minute mehr",
        "el": "Ένα λεπτό περισσότερο", "es": "Un minuto más", "fi": "Minuutti enemmän",
        "fil": "Dagdagan ng 1 minuto", "fr": "Une minute de plus", "hu": "Egy perccel több",
        "id": "Tambah 1 menit", "it": "Un minuto in più", "ja": "1分増やす", "ko": "1분 늘리기",
        "ms": "Tambah 1 minit", "nb": "Ett minutt mer", "nl": "Eén minuut meer", "pl": "Minuta więcej",
        "pt-BR": "Um minuto a mais", "pt-PT": "Mais um minuto", "ro": "Cu un minut mai mult",
        "ru": "На минуту больше", "sv": "En minut mer", "th": "เพิ่ม 1 นาที", "tr": "Bir dakika fazla",
        "uk": "На хвилину більше", "vi": "Thêm 1 phút", "zh-Hans": "增加 1 分钟", "zh-Hant": "增加 1 分鐘",
    },
    "One second less": {
        "cs": "O sekundu méně", "da": "Ét sekund mindre", "de": "Eine Sekunde weniger",
        "el": "Ένα δευτερόλεπτο λιγότερο", "es": "Un segundo menos", "fi": "Sekunti vähemmän",
        "fil": "Bawasan ng 1 segundo", "fr": "Une seconde de moins", "hu": "Egy másodperccel kevesebb",
        "id": "Kurangi 1 detik", "it": "Un secondo in meno", "ja": "1秒減らす", "ko": "1초 줄이기",
        "ms": "Kurang 1 saat", "nb": "Ett sekund mindre", "nl": "Eén seconde minder", "pl": "Sekunda mniej",
        "pt-BR": "Um segundo a menos", "pt-PT": "Menos um segundo", "ro": "Cu o secundă mai puțin",
        "ru": "На секунду меньше", "sv": "En sekund mindre", "th": "ลด 1 วินาที", "tr": "Bir saniye az",
        "uk": "На секунду менше", "vi": "Bớt 1 giây", "zh-Hans": "减少 1 秒", "zh-Hant": "減少 1 秒",
    },
    "One second more": {
        "cs": "O sekundu více", "da": "Ét sekund mere", "de": "Eine Sekunde mehr",
        "el": "Ένα δευτερόλεπτο περισσότερο", "es": "Un segundo más", "fi": "Sekunti enemmän",
        "fil": "Dagdagan ng 1 segundo", "fr": "Une seconde de plus", "hu": "Egy másodperccel több",
        "id": "Tambah 1 detik", "it": "Un secondo in più", "ja": "1秒増やす", "ko": "1초 늘리기",
        "ms": "Tambah 1 saat", "nb": "Ett sekund mer", "nl": "Eén seconde meer", "pl": "Sekunda więcej",
        "pt-BR": "Um segundo a mais", "pt-PT": "Mais um segundo", "ro": "Cu o secundă mai mult",
        "ru": "На секунду больше", "sv": "En sekund mer", "th": "เพิ่ม 1 วินาที", "tr": "Bir saniye fazla",
        "uk": "На секунду більше", "vi": "Thêm 1 giây", "zh-Hans": "增加 1 秒", "zh-Hant": "增加 1 秒",
    },
    # 2026-11-20 (#73): in-app updates. Every other update message comes from the OnePercent
    # package in the same 29 languages; only the section title and the "timer is running" refusal live here.
    "UPDATES": {
        "cs": "Aktualizace", "da": "Opdateringer", "de": "Updates", "el": "Ενημερώσεις",
        "es": "Actualizaciones", "fi": "Päivitykset", "fil": "Mga Update", "fr": "Mises à jour",
        "hu": "Frissítések", "id": "Pembaruan", "it": "Aggiornamenti", "ja": "アップデート", "ko": "업데이트",
        "ms": "Kemas Kini", "nb": "Oppdateringer", "nl": "Updates", "pl": "Uaktualnienia",
        "pt-BR": "Atualizações", "pt-PT": "Atualizações", "ro": "Actualizări", "ru": "Обновления",
        "sv": "Uppdateringar", "th": "อัปเดต", "tr": "Güncellemeler", "uk": "Оновлення", "vi": "Cập nhật",
        "zh-Hans": "更新", "zh-Hant": "更新",
    },
    "Stop the timer first to install the update.": {
        "cs": "Nejprve zastavte časovač, abyste mohli nainstalovat aktualizaci.",
        "da": "Stop timeren først for at installere opdateringen.",
        "de": "Stoppe zuerst den Timer, um das Update zu installieren.",
        "el": "Σταματήστε πρώτα τον χρονομετρητή για να εγκαταστήσετε την ενημέρωση.",
        "es": "Detén primero el temporizador para instalar la actualización.",
        "fi": "Pysäytä ajastin ensin, jotta voit asentaa päivityksen.",
        "fil": "Ihinto muna ang timer para ma-install ang update.",
        "fr": "Arrêtez d'abord le minuteur pour installer la mise à jour.",
        "hu": "A frissítés telepítéséhez először állítsa le az időzítőt.",
        "id": "Hentikan timer terlebih dahulu untuk menginstal pembaruan.",
        "it": "Ferma prima il timer per installare l'aggiornamento.",
        "ja": "アップデートをインストールするには、先にタイマーを止めてください。", "ko": "업데이트를 설치하려면 먼저 타이머를 멈춰 주세요.",
        "ms": "Hentikan pemasa dahulu untuk memasang kemas kini.",
        "nb": "Stopp timeren først for å installere oppdateringen.",
        "nl": "Stop eerst de timer om de update te installeren.",
        "pl": "Najpierw zatrzymaj licznik, aby zainstalować uaktualnienie.",
        "pt-BR": "Pare o timer primeiro para instalar a atualização.",
        "pt-PT": "Interrompe primeiro o temporizador para instalar a atualização.",
        "ro": "Oprește mai întâi cronometrul pentru a instala actualizarea.",
        "ru": "Сначала остановите таймер, чтобы установить обновление.",
        "sv": "Stoppa timern först för att installera uppdateringen.",
        "th": "โปรดหยุดตัวจับเวลาก่อนเพื่อติดตั้งการอัปเดต",
        "tr": "Güncellemeyi yüklemek için önce zamanlayıcıyı durdurun.",
        "uk": "Спочатку зупиніть таймер, щоб установити оновлення.",
        "vi": "Hãy dừng bộ đếm trước để cài bản cập nhật.", "zh-Hans": "请先停止计时，再安装更新。",
        "zh-Hant": "請先停止計時器，再安裝更新。",
    },
    "%@ remaining": {
        "cs": "Zbývá %@", "da": "%@ tilbage", "de": "Noch %@",
        "el": "Απομένουν %@", "es": "Quedan %@", "fi": "%@ jäljellä",
        "fil": "Natitirang %@", "fr": "Il reste %@", "hu": "%@ van hátra",
        "id": "Tersisa %@", "it": "Mancano %@", "ja": "残り%@",
        "ko": "%@ 남음", "ms": "Tinggal %@", "nb": "%@ igjen",
        "nl": "Nog %@", "pl": "Pozostało %@", "pt-BR": "Faltam %@",
        "pt-PT": "Faltam %@", "ro": "Au mai rămas %@", "ru": "Осталось %@",
        "sv": "%@ kvar", "th": "เหลืออีก %@", "tr": "%@ kaldı",
        "uk": "Залишилося %@", "vi": "Còn lại %@",
        "zh-Hans": "剩余%@", "zh-Hant": "剩餘%@",
    },
}

def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")

written = []
for code, trans in by_lang.items():
    if code == "en":
        continue
    lproj = os.path.join(res_dir, f"{code}.lproj")
    os.makedirs(lproj, exist_ok=True)
    lines = [f"/* PomoLight — {code} (auto-assembled) */"]
    missing = 0
    all_keys = [k for k in list(keys) + [k for k in MANUAL if k not in keys]
                if k not in SKIP_KEYS]
    for k in all_keys:
        v = trans.get(k)
        if not v or not str(v).strip():
            v = MANUAL.get(k, {}).get(code)
        if not v or not str(v).strip():
            v = k          # fall back to English
            missing += 1
        lines.append(f'"{esc(k)}" = "{esc(str(v))}";')
    with open(os.path.join(lproj, "Localizable.strings"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    written.append((code, len(trans), missing))

print(f"Wrote {len(written)} localizations:")
for code, have, missing in sorted(written):
    flag = "" if missing == 0 else f"  ⚠ {missing} fell back to EN"
    print(f"  {code:8} {have} keys{flag}")
