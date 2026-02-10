import sqlite3, requests, json, os, random, threading, re, webbrowser
from kivy.app import App
from kivy.clock import mainthread, Clock
from kivy.uix.floatlayout import FloatLayout
from kivy.uix.anchorlayout import AnchorLayout
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.gridlayout import GridLayout
from kivy.uix.button import Button
from kivy.uix.label import Label
from kivy.uix.slider import Slider
from kivy.uix.image import AsyncImage
from kivy.uix.textinput import TextInput
from kivy.uix.screenmanager import ScreenManager, Screen, FadeTransition
from kivy.core.audio import SoundLoader
from kivy.core.window import Window
from kivy.core.clipboard import Clipboard
from kivy.graphics import Color, RoundedRectangle, Line, Rectangle
from kivy.properties import StringProperty

# 1. OLED Black
Window.clearcolor = (0, 0, 0, 1)

# 2. Crash-Proof Storage (No Android Imports)
# We save directly to the folder where the script is running.
DEFAULT_STORAGE = os.path.join(os.getcwd(), 'ZenSei_Music')
if not os.path.exists(DEFAULT_STORAGE):
    try:
        os.makedirs(DEFAULT_STORAGE)
    except:
        pass

# 3. Database
def get_db_path(): return os.path.join(DEFAULT_STORAGE, 'zensei_platinum.db')
def init_db():
    try:
        conn = sqlite3.connect(get_db_path(), check_same_thread=False)
        cur = conn.cursor()
        cur.execute('''CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)''')
        cur.execute('''CREATE TABLE IF NOT EXISTS tracks (id TEXT PRIMARY KEY, name TEXT, art TEXT, is_local INTEGER)''')
        cur.execute("SELECT value FROM settings WHERE key='bridge_url'")
        if not cur.fetchone():
            cur.execute("INSERT INTO settings VALUES ('bridge_url', 'https://script.google.com/macros/s/AKfycbx5yN9YWgHn1NjLHvjoRX1qQ1tOdH3RbTiBLlRUw4XPsYM96yVP5TIDz6OZLyeiKFfa/exec')")
        conn.commit()
        conn.close()
    except: pass

# 4. Visual Components
class GlassPanel(BoxLayout):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.padding = 20
        with self.canvas.before:
            Color(1, 1, 1, 0.05)
            self.rect = RoundedRectangle(pos=self.pos, size=self.size, radius=[20])
        self.bind(pos=self.update_rect, size=self.update_rect)
    def update_rect(self, *args):
        self.rect.pos = self.pos
        self.rect.size = self.size

class GlassButton(Button):
    def __init__(self, icon_type=None, bg_color=(1,1,1,0.08), **kwargs):
        super().__init__(**kwargs)
        self.icon_type = icon_type
        self.bg_color = bg_color
        self.background_normal = ''
        self.background_color = (0, 0, 0, 0)
        self.bind(pos=self.redraw, size=self.redraw)
        
    def redraw(self, *args):
        self.canvas.after.clear()
        with self.canvas.after:
            Color(*self.bg_color)
            RoundedRectangle(pos=self.pos, size=self.size, radius=[15])
            if self.icon_type:
                if self.icon_type == "repeat_one": Color(0, 0.8, 1, 1)
                elif self.icon_type == "repeat_all": Color(0, 1, 0.5, 1)
                elif self.icon_type == "pause": Color(1, 0.8, 0.2, 1) # Gold for pause
                else: Color(1, 1, 1, 0.9)
                
                cx, cy = self.center; s = min(self.width, self.height) * 0.25
                if self.icon_type == "play":
                    Line(points=[cx-s/2, cy+s, cx-s/2, cy-s, cx+s, cy], close=True, width=2)
                elif self.icon_type == "pause":
                    Line(points=[cx-6, cy-s, cx-6, cy+s], width=3)
                    Line(points=[cx+6, cy-s, cx+6, cy+s], width=3)
                elif self.icon_type == "next":
                    Line(points=[cx-s, cy-s, cx-s, cy+s, cx, cy], close=True, width=2)
                    Line(points=[cx, cy-s, cx, cy+s, cx+s, cy], close=True, width=2)
                elif self.icon_type == "prev":
                    Line(points=[cx+s, cy-s, cx+s, cy+s, cx, cy], close=True, width=2)
                    Line(points=[cx, cy-s, cx, cy+s, cx-s, cy], close=True, width=2)
                elif self.icon_type == "library":
                    Line(points=[cx-s, cy+6, cx+s, cy+6], width=2)
                    Line(points=[cx-s, cy, cx+s, cy], width=2)
                    Line(points=[cx-s, cy-6, cx+s, cy-6], width=2)
                elif self.icon_type == "close":
                    Line(points=[cx-s, cy-s, cx+s, cy+s], width=2)
                    Line(points=[cx+s, cy-s, cx-s, cy+s], width=2)
                elif "repeat" in self.icon_type:
                    Line(circle=(cx, cy, s), width=2, angle_start=45, angle_end=315)
                    Line(points=[cx+s-3, cy+s-3, cx+s+5, cy+s+5], width=2)

class BackgroundScreen(Screen):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.bg = AsyncImage(allow_stretch=True, keep_ratio=False, opacity=0.3, fit_mode="cover")
        self.add_widget(self.bg)
        App.get_running_app().bind(current_bg=self.bg.setter('source'))

# 5. App Logic
class ZenSeiApp(App):
    current_bg = StringProperty('https://images.unsplash.com/photo-1494232410401-ad00d5433cfa')

    def build(self):
        init_db()
        self.sound = None
        self.repeat = 0
        self.dragging = False
        self.paused_pos = 0 
        
        self.sm = ScreenManager(transition=FadeTransition(duration=0.5))
        self.sm.add_widget(self.build_splash())
        self.sm.add_widget(self.build_main())
        self.sm.add_widget(self.build_library())
        self.sm.add_widget(self.build_settings())
        self.sm.add_widget(self.build_advanced())
        self.sm.add_widget(self.build_drive_setup())
        self.sm.add_widget(self.build_donate())
        
        return self.sm

    def on_pause(self): return True

    # --- SCREEN 1: SPLASH ---
    def build_splash(self):
        s = Screen(name='splash')
        with s.canvas.before:
            Color(0, 0, 0, 1)
            Rectangle(pos=(0,0), size=(Window.width, Window.height))
        
        root = FloatLayout()
        root.add_widget(Label(text="Z E N S E I", font_size='60sp', bold=True, pos_hint={'center_x':0.5, 'center_y':0.5}))
        s.add_widget(root)
        threading.Thread(target=self.sync_worker, args=(self.get_bridge_url(),), daemon=True).start()
        Clock.schedule_once(lambda dt: setattr(self.sm, 'current', 'main'), 3.5)
        return s

    # --- SCREEN 2: MAIN ---
    def build_main(self):
        s = BackgroundScreen(name='main')
        
        # Header (Top Anchor)
        top = AnchorLayout(anchor_x='center', anchor_y='top', padding=[20, 60, 20, 0])
        self.marquee_box = GlassPanel(size_hint=(0.95, None), height=140)
        self.marquee_lbl = Label(text="ZENSEI • READY", font_size='22sp', bold=True)
        self.marquee_box.add_widget(self.marquee_lbl)
        top.add_widget(self.marquee_box)
        s.add_widget(top)
        Clock.schedule_interval(self.scroll_text, 0.03)

        # Controls (Bottom Anchor)
        bot = AnchorLayout(anchor_x='center', anchor_y='bottom', padding=[20, 0, 20, 30])
        panel = GlassPanel(orientation='vertical', size_hint=(0.95, None), height=550, spacing=20)
        
        # Seeker
        self.bar = Slider(min=0, max=100, value=0, cursor_size=(50, 50), value_track=True, value_track_color=(0.2, 0.8, 1, 1))
        self.bar.bind(on_touch_down=self.seek_start, on_touch_up=self.seek_end)
        panel.add_widget(self.bar)
        
        # Grid Buttons
        grid = GridLayout(cols=5, spacing=15, size_hint_y=None, height=120)
        self.btn_rep = GlassButton("repeat", on_release=self.toggle_repeat)
        self.btn_play = GlassButton("play", on_release=self.toggle_play)
        
        grid.add_widget(self.btn_rep)
        grid.add_widget(GlassButton("prev", on_release=lambda x: self.skip(-1)))
        grid.add_widget(self.btn_play)
        grid.add_widget(GlassButton("next", on_release=lambda x: self.skip(1)))
        grid.add_widget(GlassButton("library", on_release=lambda x: setattr(self.sm, 'current', 'library')))
        panel.add_widget(grid)
        
        # EQ Visuals (Fixed Syntax)
        self.eq_box = BoxLayout(spacing=5, size_hint_y=None, height=60)
        self.bars = []
        for _ in range(20):
            b = BoxLayout()
            with b.canvas:
                Color(0.2, 0.8, 1, 0.5)
                b.rect = RoundedRectangle(pos=b.pos, size=(10, 10))
            self.bars.append(b)
            self.eq_box.add_widget(b)
        panel.add_widget(self.eq_box)
        Clock.schedule_interval(self.anim_eq, 0.1)

        # Settings Button
        set_btn = GlassButton(text="SETTINGS", size_hint=(None, None), size=(200, 50), pos_hint={'center_x': 0.5})
        set_btn.bind(on_release=lambda x: setattr(self.sm, 'current', 'settings'))
        panel.add_widget(set_btn)
        
        bot.add_widget(panel)
        s.add_widget(bot)
        Clock.schedule_interval(self.update_loop, 0.5)
        return s

    # --- SCREEN 3: SETTINGS ---
    def build_settings(self):
        s = BackgroundScreen(name='settings')
        anc = AnchorLayout(anchor_x='center', anchor_y='center', padding=20)
        root = GlassPanel(orientation='vertical', spacing=15)
        
        root.add_widget(Label(text="SETTINGS", font_size='32sp', bold=True, size_hint_y=None, height=60))
        
        status_box = BoxLayout(size_hint_y=None, height=40)
        status_box.add_widget(Label(text="STATUS: CONNECTED", color=(0,1,0.5,1), bold=True))
        root.add_widget(status_box)
        
        resync = GlassButton(text="FORCE RESYNC LIBRARY", size_hint_y=None, height=60, bg_color=(0.2, 0.8, 1, 0.3))
        resync.bind(on_release=lambda x: threading.Thread(target=self.sync_worker, args=(self.get_bridge_url(),), daemon=True).start())
        root.add_widget(resync)

        adv = GlassButton(text="ADVANCED CONNECTION", size_hint_y=None, height=60)
        adv.bind(on_release=lambda x: setattr(self.sm, 'current', 'advanced'))
        root.add_widget(adv)

        donate = GlassButton(text="SUPPORT / DONATE", size_hint_y=None, height=60, bg_color=(1, 0.4, 0.4, 0.3))
        donate.bind(on_release=lambda x: setattr(self.sm, 'current', 'donate'))
        root.add_widget(donate)

        back = GlassButton(text="BACK TO PLAYER", size_hint_y=None, height=60)
        back.bind(on_release=lambda x: setattr(self.sm, 'current', 'main'))
        root.add_widget(back)
        
        anc.add_widget(root)
        s.add_widget(anc)
        return s

    # --- SCREEN 4: DONATE ---
    def build_donate(self):
        s = BackgroundScreen(name='donate')
        anc = AnchorLayout(anchor_x='center', anchor_y='center', padding=30)
        panel = GlassPanel(orientation='vertical', spacing=20)
        
        panel.add_widget(Label(text="SUPPORT ZENSEI", font_size='30sp', bold=True, size_hint_y=None, height=60))
        
        msg = "If you enjoy using ZenSei, consider tipping to support future updates."
        panel.add_widget(Label(text=msg, font_size='18sp', halign='center', valign='middle', text_size=(Window.width-80, None)))
        
        kofi_btn = GlassButton(text="OPEN KO-FI PAGE", size_hint_y=None, height=80, bg_color=(0.2, 0.7, 1, 0.6))
        kofi_btn.bind(on_release=lambda x: webbrowser.open("https://ko-fi.com/zenseimusic"))
        panel.add_widget(kofi_btn)

        back = GlassButton(text="BACK", size_hint_y=None, height=60)
        back.bind(on_release=lambda x: setattr(self.sm, 'current', 'settings'))
        panel.add_widget(back)
        
        anc.add_widget(panel)
        s.add_widget(anc)
        return s

    # --- SCREEN 5: ADVANCED ---
    def build_advanced(self):
        s = BackgroundScreen(name='advanced')
        anc = AnchorLayout(anchor_x='center', anchor_y='center', padding=20)
        root = GlassPanel(orientation='vertical', spacing=15)
        root.add_widget(Label(text="CONNECTION SETUP", font_size='24sp', bold=True, size_hint_y=None, height=50))
        root.add_widget(Label(text="GOOGLE APPS SCRIPT URL:", size_hint_y=None, height=30, color=(0.7,0.7,0.7,1)))
        self.drive_in = TextInput(text=self.get_bridge_url(), multiline=False, size_hint_y=None, height=50, foreground_color=(1,1,1,1), background_color=(0,0,0,0.3), hint_text="Paste Bridge URL...")
        root.add_widget(self.drive_in)
        save = GlassButton(text="SAVE URL", size_hint_y=None, height=50, bg_color=(0.2, 1, 0.5, 0.3))
        save.bind(on_release=self.save_settings)
        root.add_widget(save)
        setup = GlassButton(text="HOW TO SETUP DRIVE?", size_hint_y=None, height=50)
        setup.bind(on_release=lambda x: setattr(self.sm, 'current', 'drive_setup'))
        root.add_widget(setup)
        back = GlassButton(text="BACK", size_hint_y=None, height=60)
        back.bind(on_release=lambda x: setattr(self.sm, 'current', 'settings'))
        root.add_widget(back)
        anc.add_widget(root)
        s.add_widget(anc)
        return s

    # --- SCREEN 6: DRIVE SETUP ---
    def build_drive_setup(self):
        s = BackgroundScreen(name='drive_setup')
        root = BoxLayout(orientation='vertical', padding=[20, 50, 20, 20], spacing=10)
        
        # Instructions
        instr_box = GlassPanel(orientation='vertical', size_hint_y=0.4, spacing=5)
        instr_box.add_widget(Label(text="SETUP INSTRUCTIONS", font_size='22sp', bold=True, size_hint_y=None, height=40))
        txt = "1. Create folder 'ZenSei_Music' in Google Drive.\n2. Upload MP3s.\n3. Go to script.google.com -> New Project.\n4. Paste the code below & Save.\n5. Click Deploy -> New Deployment.\n6. Type: Web App -> Access: Anyone.\n7. Copy URL -> ZenSei Settings."
        instr_label = Label(text=txt, halign='left', valign='top')
        instr_label.bind(size=instr_label.setter('text_size'))
        instr_box.add_widget(instr_label)
        root.add_widget(instr_box)
        
        # Code Box
        code = "function doGet() {\n  var f = DriveApp.getFoldersByName('ZenSei_Music').next();\n  var files = f.getFiles();\n  var list = [];\n  while (files.hasNext()) {\n    var file = files.next();\n    list.push({id: file.getId(), name: file.getName()});\n  }\n  return ContentService.createTextOutput(JSON.stringify(list)).setMimeType(ContentService.MimeType.JSON);\n}"
        code_box = GlassPanel(orientation='vertical', size_hint_y=0.45, spacing=5)
        code_box.add_widget(TextInput(text=code, readonly=True, background_color=(0,0,0,0.3), foreground_color=(0.5,1,0.5,1)))
        
        copy_btn = GlassButton(text="COPY CODE", size_hint_y=None, height=50, bg_color=(0.2, 0.8, 1, 0.3))
        copy_btn.bind(on_release=lambda x: Clipboard.copy(code))
        code_box.add_widget(copy_btn)
        
        back = GlassButton(text="BACK", size_hint_y=None, height=60)
        back.bind(on_release=lambda x: setattr(self.sm, 'current', 'advanced'))
        root.add_widget(back)
        s.add_widget(root)
        return s

    # --- SCREEN 7: LIBRARY ---
    def build_library(self):
        s = BackgroundScreen(name='library')
        anc = AnchorLayout(anchor_x='center', anchor_y='center', padding=30)
        panel = GlassPanel(orientation='vertical', spacing=10)
        h = BoxLayout(size_hint_y=None, height=80)
        h.add_widget(Label(text="LIBRARY", font_size='30sp', bold=True, halign='left'))
        h.add_widget(GlassButton("close", size_hint_x=None, width=80, on_release=lambda x: setattr(self.sm, 'current', 'main')))
        panel.add_widget(h)
        from kivy.uix.scrollview import ScrollView
        sv = ScrollView()
        self.lib_grid = GridLayout(cols=1, spacing=10, size_hint_y=None)
        self.lib_grid.bind(minimum_height=self.lib_grid.setter('height'))
        sv.add_widget(self.lib_grid)
        panel.add_widget(sv)
        anc.add_widget(panel)
        s.add_widget(anc)
        return s

    # --- LOGIC ---
    def get_bridge_url(self):
        try:
            conn = sqlite3.connect(get_db_path())
            cur = conn.cursor()
            cur.execute("SELECT value FROM settings WHERE key='bridge_url'")
            row = cur.fetchone()
            conn.close()
            return row[0] if row else ''
        except: return ''

    @mainthread
    def scroll_text(self, dt):
        self.marquee_lbl.x -= 2
        if self.marquee_lbl.right < 0: self.marquee_lbl.x = Window.width

    def seek_start(self, inst, touch):
        if inst.collide_point(*touch.pos): self.dragging = True

    def seek_end(self, inst, touch):
        if self.dragging:
            if self.sound: self.sound.seek(self.bar.value)
            self.dragging = False

    @mainthread
    def anim_eq(self, dt):
        if self.sound and self.sound.state == 'play':
            for b in self.bars:
                h = random.randint(10, 50)
                b.rect.size = (10, h)
                b.rect.pos = (b.x, b.y)
        else:
            for b in self.bars: b.rect.size = (10, 5)

    def toggle_play(self, *args):
        if self.sound:
            if self.sound.state == 'play':
                self.paused_pos = self.sound.get_pos()
                self.sound.stop()
                self.btn_play.icon_type = "play"
            else:
                self.sound.play()
                self.sound.seek(self.paused_pos)
                self.btn_play.icon_type = "pause"
            self.btn_play.redraw()

    @mainthread
    def update_loop(self, dt):
        if self.sound and self.sound.state == 'play' and not self.dragging:
            self.bar.max = self.sound.length
            self.bar.value = self.sound.get_pos()
            if (self.sound.length - self.sound.get_pos()) < 1.0:
                if self.repeat == 1: self.sound.seek(0)
                elif self.repeat == 2: self.skip(1)

    def toggle_repeat(self, *args):
        self.repeat = (self.repeat + 1) % 3
        modes = ["repeat", "repeat_one", "repeat_all"]
        self.btn_rep.icon_type = modes[self.repeat]
        self.btn_rep.redraw()

    def skip(self, direction): pass

    def save_settings(self, *args):
        url = self.drive_input.text
        conn = sqlite3.connect(get_db_path())
        cur = conn.cursor()
        cur.execute("UPDATE settings SET value=? WHERE key='bridge_url'", (url,))
        conn.commit()
        conn.close()
        threading.Thread(target=self.sync_worker, args=(url,), daemon=True).start()
        setattr(self.sm, 'current', 'settings')

    def sync_worker(self, url):
        try:
            r = requests.get(url, timeout=15).json()
            conn = sqlite3.connect(get_db_path())
            cur = conn.cursor()
            for x in r:
                clean = re.sub(r'[-_\.]', ' ', x['name'].rsplit('.', 1)[0]).upper()
                art = 'https://images.unsplash.com/photo-1494232410401-ad00d5433cfa'
                try:
                    m = requests.get(f"https://itunes.apple.com/search?term={clean}&limit=1&entity=song").json()
                    if m['resultCount'] > 0: art = m['results'][0]['artworkUrl100'].replace('100x100bb.jpg', '1000x1000bb.jpg')
                except: pass
                cur.execute("INSERT OR IGNORE INTO tracks VALUES (?, ?, ?, 0)", (x['id'], x['name'], art))
            conn.commit()
            conn.close()
            Clock.schedule_once(self.refresh_lib)
        except: pass

    @mainthread
    def refresh_lib(self, dt):
        self.lib_grid.clear_widgets()
        conn = sqlite3.connect(get_db_path())
        cur = conn.cursor()
        cur.execute("SELECT * FROM tracks")
        for t in cur.fetchall():
            btn = GlassButton(text=t[1], size_hint_y=None, height=80, bg_color=(1,1,1,0.05))
            btn.bind(on_release=lambda x, track=t: self.play_track(track))
            self.lib_grid.add_widget(btn)
        conn.close()

    @mainthread
    def play_track(self, track):
        if self.sound: self.sound.stop()
        fid, name, art, is_local = track
        self.marquee_lbl.text = f"{name}   •   {name}"
        self.current_bg 