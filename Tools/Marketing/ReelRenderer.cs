using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

internal static class ReelRenderer
{
    const int W = 720, H = 1280, Fps = 24, Seconds = 52;
    static readonly Color Ink = Color.FromArgb(23, 22, 19);
    static readonly Color Paper = Color.FromArgb(226, 222, 214);
    static readonly Color Warm = Color.FromArgb(179, 173, 162);
    static readonly Color Gold = Color.FromArgb(199, 153, 55);
    static readonly Color Red = Color.FromArgb(143, 31, 31);
    static readonly Font Big = new Font("Arial", 48, FontStyle.Bold);
    static readonly Font H1 = new Font("Arial", 31, FontStyle.Bold);
    static readonly Font H2 = new Font("Arial", 19, FontStyle.Bold);
    static readonly Font Body = new Font("Arial", 15, FontStyle.Regular);
    static readonly Font Small = new Font("Arial", 11, FontStyle.Bold);

    static float Clamp(float v) { return Math.Max(0, Math.Min(1, v)); }
    static float Ease(float v) { v = Clamp(v); return 1f - (float)Math.Pow(1f - v, 3); }
    static float Pulse(float v) { return .5f - .5f * (float)Math.Cos(v * Math.PI * 2); }

    static GraphicsPath RoundRect(RectangleF r, float radius)
    {
        float d = radius * 2;
        var p = new GraphicsPath();
        p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure(); return p;
    }

    static void FillRound(Graphics g, Brush b, RectangleF r, float radius)
    { using (var p = RoundRect(r, radius)) g.FillPath(b, p); }

    static void Line(Graphics g, string text, Font f, Brush b, RectangleF r, StringAlignment align = StringAlignment.Near)
    {
        using (var sf = new StringFormat { Alignment = align, LineAlignment = StringAlignment.Center, Trimming = StringTrimming.EllipsisCharacter })
            g.DrawString(text, f, b, r, sf);
    }

    static void Label(Graphics g, string text, float x, float y, Color color)
    {
        var size = g.MeasureString(text, Small);
        var r = new RectangleF(x, y, size.Width + 22, 31);
        FillRound(g, new SolidBrush(color), r, 15);
        Line(g, text, Small, color == Ink ? Brushes.White : Brushes.Black, r, StringAlignment.Center);
    }

    static void Header(Graphics g, string kicker, string title, string subtitle, float reveal)
    {
        float x = 42 + (1 - Ease(reveal)) * 55;
        Label(g, kicker, x, 45, Gold);
        Line(g, title, H1, Brushes.White, new RectangleF(x, 86, 640, 82));
        Line(g, subtitle, Body, new SolidBrush(Color.FromArgb(210, 220, 216, 208)), new RectangleF(x, 160, 632, 58));
    }

    static void Background(Graphics g, float t)
    {
        g.Clear(Ink);
        using (var b = new LinearGradientBrush(new Rectangle(0, 0, W, H), Color.FromArgb(46, 44, 40), Color.FromArgb(16, 16, 15), 70f)) g.FillRectangle(b, 0, 0, W, H);
        using (var p = new Pen(Color.FromArgb(24, 255, 255, 255), 1))
            for (int y = -100 + ((int)(t * 18) % 100); y < H; y += 100) g.DrawLine(p, 0, y, W, y + 180);
        for (int i = 0; i < 34; i++)
        {
            float h = 8 + (float)Math.Abs(Math.Sin(i * .71 + t * 3.2)) * 44;
            using (var b = new SolidBrush(Color.FromArgb(30, 199, 153, 55))) g.FillRectangle(b, i * 23 - 20, H - 85 - h, 7, h);
        }
    }

    static void ImageCard(Graphics g, Image image, Rectangle src, RectangleF dst, float progress, Color accent, bool glow = true)
    {
        float enter = Ease(progress);
        dst.Y += (1 - enter) * 95;
        if (glow) using (var shadow = new SolidBrush(Color.FromArgb((int)(70 * enter), accent))) FillRound(g, shadow, new RectangleF(dst.X - 10, dst.Y - 10, dst.Width + 20, dst.Height + 20), 25);
        var state = g.Save();
        using (var clip = RoundRect(dst, 18)) { g.SetClip(clip); g.DrawImage(image, dst, src, GraphicsUnit.Pixel); }
        g.Restore(state);
        using (var pen = new Pen(Color.FromArgb((int)(230 * enter), accent), 3)) using (var p = RoundRect(dst, 18)) g.DrawPath(pen, p);
    }

    static void CameraFrame(Graphics g, Image image, RectangleF from, RectangleF to, RectangleF dst, float move, float reveal, Color accent)
    {
        float m = Ease(move), enter = Ease(reveal);
        var src = new RectangleF(
            from.X + (to.X - from.X) * m,
            from.Y + (to.Y - from.Y) * m,
            from.Width + (to.Width - from.Width) * m,
            from.Height + (to.Height - from.Height) * m);
        dst.Y += (1 - enter) * 80;
        using (var glow = new SolidBrush(Color.FromArgb((int)(54 * enter), accent))) FillRound(g, glow, new RectangleF(dst.X - 9, dst.Y - 9, dst.Width + 18, dst.Height + 18), 26);
        var state = g.Save();
        using (var clip = RoundRect(dst, 18)) { g.SetClip(clip); g.DrawImage(image, dst, src, GraphicsUnit.Pixel); }
        g.Restore(state);
        using (var pen = new Pen(Color.FromArgb((int)(225 * enter), accent), 3)) using (var path = RoundRect(dst, 18)) g.DrawPath(pen, path);
    }

    static void FocusTag(Graphics g, string text, float x, float y, float progress)
    {
        float p = Ease(progress);
        var size = g.MeasureString(text, Small);
        var r = new RectangleF(x + (1-p)*30, y, size.Width + 24, 34);
        FillRound(g, new SolidBrush(Color.FromArgb((int)(245*p), Gold)), r, 17);
        Line(g, text, Small, Brushes.Black, r, StringAlignment.Center);
    }

    static void UiPanel(Graphics g, RectangleF r, Color fill, float radius = 16)
    {
        FillRound(g, new SolidBrush(fill), r, radius);
        using(var p=new Pen(Color.FromArgb(105,89,85,78),2)) using(var path=RoundRect(r,radius)) g.DrawPath(p,path);
    }

    static void UiButton(Graphics g, string text, RectangleF r, bool primary=false)
    {
        FillRound(g,new SolidBrush(primary?Ink:Color.FromArgb(207,203,195)),r,8);
        Line(g,text,Small,primary?Brushes.White:Brushes.Black,r,StringAlignment.Center);
    }

    static void UiField(Graphics g, string label, string value, RectangleF r)
    {
        Line(g,label,Small,new SolidBrush(Color.FromArgb(70,66,60)),new RectangleF(r.X,r.Y-28,r.Width,24));
        FillRound(g,new SolidBrush(Color.FromArgb(245,243,238)),r,7);
        Line(g,value,Body,Brushes.Black,new RectangleF(r.X+14,r.Y,r.Width-28,r.Height));
    }

    static void Cover(Graphics g, RectangleF r, Color a, Color b, int seed)
    {
        using(var brush=new LinearGradientBrush(r,a,b,45+seed*20)) g.FillRectangle(brush,r);
        using(var pen=new Pen(Color.FromArgb(155,255,255,255),2))
            for(int i=0;i<4;i++) g.DrawEllipse(pen,r.X+8+i*5,r.Y+8+i*4,r.Width-16-i*10,r.Height-16-i*8);
    }

    static void Stat(Graphics g,string label,string value,RectangleF r,Color valueColor)
    {
        UiPanel(g,r,Color.FromArgb(235,232,225),12);
        Line(g,label,Small,new SolidBrush(Color.FromArgb(74,70,64)),new RectangleF(r.X+14,r.Y+8,r.Width-28,28));
        Line(g,value,H1,new SolidBrush(valueColor),new RectangleF(r.X+14,r.Y+34,r.Width-28,r.Height-40));
    }

    static void ProgressArrow(Graphics g, float y, int active)
    {
        string[] steps = { "BAIXE", "ORGANIZE", "REKORDBOX", "AUDITE", "PROTEJA O USB" };
        int[] widths = { 96, 106, 124, 96, 145 };
        float x = 42;
        for (int i = 0; i < steps.Length; i++)
        {
            var c = i <= active ? Gold : Color.FromArgb(85, 82, 77);
            var width = widths[i];
            FillRound(g, new SolidBrush(c), new RectangleF(x, y, width, 36), 18);
            Line(g, steps[i], new Font("Arial", 9, FontStyle.Bold), i <= active ? Brushes.Black : Brushes.White, new RectangleF(x, y, width, 36), StringAlignment.Center);
            x += width + 7;
        }
    }

    static void DrawIntro(Graphics g, Image logo, float t)
    {
        float e = Ease(t / 1.4f);
        float logoSize = 122 + 18 * Pulse(t * .22f);
        g.DrawImage(logo, (W - logoSize) / 2, 205 - (1 - e) * 90, logoSize, logoSize);
        Line(g, "CRIVO DJ", Big, Brushes.White, new RectangleF(30, 350, W - 60, 80), StringAlignment.Center);
        using (var b = new SolidBrush(Gold)) g.FillRectangle(b, 190, 448, 340 * e, 5);
        Line(g, "DO DOWNLOAD DA MÚSICA", H2, Brushes.White, new RectangleF(40, 475, W - 80, 52), StringAlignment.Center);
        Line(g, "AO REKORDBOX", H1, new SolidBrush(Gold), new RectangleF(40, 520, W - 80, 70), StringAlignment.Center);
        Label(g, "OU COMECE POR UMA PASTA QUE VOCÊ JÁ TEM", 145, 625, Paper);
        Line(g, "um fluxo portátil para pesquisa, organização e revisão", Body, new SolidBrush(Warm), new RectangleF(65, 690, W - 130, 70), StringAlignment.Center);
        ProgressArrow(g, 850, -1);
    }

    static void DrawDownload(Graphics g, Image shot, float t)
    {
        Header(g,"01  BAIXAR","COLE O LINK DE TRACKS OU PLAYLISTS.","YouTube, SoundCloud e Spotify entram na mesma lista.",t/.9f);
        float p=Ease(t/1.1f), y=265+(1-p)*90;
        UiPanel(g,new RectangleF(30,y,660,825),Color.FromArgb(190,186,178),22);
        UiField(g,"LINK DA TRACK OU PLAYLIST","https://soundcloud.com/pesquisa/outubro",new RectangleF(52,y+62,475,54));
        UiButton(g,"ADICIONAR",new RectangleF(539,y+62,126,54),true);
        string[] names={"Midnight Signal","Low Pressure","Sunday Service (Club Mix)","Glass Rooms"};
        string[] artists={"Aurora Lines","Nilo S.","Mabel Costa","Theo Vale"};
        string[] sources={"SoundCloud","YouTube","Spotify","SoundCloud"};
        int[] progress={100,100,68,0};
        Color[] ca={Color.FromArgb(19,64,98),Color.FromArgb(95,95,38),Color.FromArgb(220,45,94),Color.FromArgb(53,31,91)};
        for(int i=0;i<4;i++){
            float rowP=Ease((t-.7f-i*.18f)/.65f); float ry=y+155+i*142+(1-rowP)*35;
            UiPanel(g,new RectangleF(48,ry,624,128),i%2==0?Color.FromArgb(230,227,220):Color.FromArgb(217,213,205),9);
            Cover(g,new RectangleF(64,ry+18,82,82),ca[i],Color.Black,i);
            Line(g,names[i],H2,Brushes.Black,new RectangleF(162,ry+12,300,34));
            Line(g,artists[i]+"  •  "+sources[i],Body,new SolidBrush(Color.FromArgb(72,68,62)),new RectangleF(162,ry+47,320,30));
            FillRound(g,new SolidBrush(Color.FromArgb(155,151,144)),new RectangleF(475,ry+42,170,14),7);
            if(progress[i]>0) FillRound(g,new SolidBrush(Ink),new RectangleF(475,ry+42,170*progress[i]/100f,14),7);
            Line(g,progress[i]==0?"PRONTA":progress[i]+"%",Small,Brushes.Black,new RectangleF(475,ry+65,170,25),StringAlignment.Center);
        }
        FocusTag(g,"CAPAS • FONTES • PROGRESSO",48,1115,Clamp((t-2)/.8f));
    }

    static void DrawOrganize(Graphics g, Image shot, float t)
    {
        Header(g,"02  ORGANIZAR","ORGANIZE AS MÚSICAS JÁ BAIXADAS.","Ou escolha qualquer pasta que já exista no computador.",t/.9f);
        float p=Ease(t/1.0f), y=260+(1-p)*80;
        UiPanel(g,new RectangleF(28,y,664,810),Color.FromArgb(190,186,178),22);
        Stat(g,"TRACKS AO TODO","6",new RectangleF(48,y+28,292,105),Ink);
        Stat(g,"DADOS FALTANTES","3",new RectangleF(352,y+28,318,105),Gold);
        string[] tracks={"Aurora Lines - Midnight Signal.mp3","Nilo S. - Low Pressure.mp3","Mabel Costa - Sunday Service.mp3","Theo Vale - Glass Rooms.mp3"};
        string[] data={"DADOS COMPLETOS","DADOS COMPLETOS","ANO FALTANTE","ÁLBUM E ANO FALTANTES"};
        Line(g,"NOME FINAL",Small,Brushes.Black,new RectangleF(65,y+170,360,28));
        Line(g,"DADOS",Small,Brushes.Black,new RectangleF(445,y+170,205,28));
        for(int i=0;i<4;i++){
            float ry=y+204+i*72; UiPanel(g,new RectangleF(48,ry,622,62),i%2==0?Color.FromArgb(232,229,222):Color.FromArgb(218,214,206),5);
            Line(g,tracks[i],Body,Brushes.Black,new RectangleF(64,ry,365,62));
            Line(g,data[i],Small,i<2?new SolidBrush(Color.FromArgb(54,92,57)):new SolidBrush(Red),new RectangleF(445,ry,205,62));
        }
        UiPanel(g,new RectangleF(48,y+525,622,178),Color.FromArgb(230,227,220),10);
        Line(g,"REKORDBOX",Small,new SolidBrush(Color.FromArgb(72,68,62)),new RectangleF(68,y+540,160,28));
        Line(g,"✓  Gravar playlist diretamente no Rekordbox",H2,Brushes.Black,new RectangleF(68,y+572,550,42));
        UiField(g,"NOME DA PLAYLIST","Pesquisa Outubro — Organizado",new RectangleF(68,y+650,430,48));
        UiButton(g,"ORGANIZAR",new RectangleF(510,y+650,140,48),true);
        if(t>4.5f) FocusTag(g,"CRIAR PLAYLIST DIRETO NO REKORDBOX",48,1095,Clamp((t-4.5f)/.8f));
    }

    static void DrawAudit(Graphics g, Image shot, float t)
    {
        Header(g,"03  AUDITORIA","REVISE REKORDBOX OU PENDRIVE.","Problema, causa e playlist aparecem juntos antes de qualquer decisão.",t/.9f);
        float p=Ease(t/1.0f),y=260+(1-p)*80;
        UiPanel(g,new RectangleF(28,y,664,820),Color.FromArgb(190,186,178),22);
        Stat(g,"TRACKS","7",new RectangleF(46,y+26,145,102),Ink);
        Stat(g,"AUSENTES","1",new RectangleF(201,y+26,145,102),Red);
        Stat(g,"DADOS","2",new RectangleF(356,y+26,145,102),Gold);
        Stat(g,"DUPLICADAS","1",new RectangleF(511,y+26,161,102),Red);
        string[] title={"Midnight Signal","Sunday Service","Glass Rooms","Soft Focus","Afterimage","Parallel Lines"};
        string[] issue={"Saudável","Qualidade suspeita","Dados faltantes","Duplicada","Análise ausente","Arquivo ausente"};
        string[] diag={"Nenhum problema","Bitrate abaixo do padrão","Álbum e ano não informados","Mesmo áudio em duas pastas","Waveform ainda não gerada","Caminho não encontrado"};
        string[] list={"Warm Up","Vocals","After Hours","Peak Time","Opening","Electro"};
        Line(g,"TRACK",Small,Brushes.Black,new RectangleF(55,y+155,190,28)); Line(g,"PROBLEMA",Small,Brushes.Black,new RectangleF(250,y+155,150,28));
        Line(g,"DIAGNÓSTICO / PLAYLIST",Small,Brushes.Black,new RectangleF(410,y+155,240,28));
        for(int i=0;i<6;i++){
            float rp=Ease((t-.7f-i*.1f)/.55f),ry=y+190+i*92+(1-rp)*28; UiPanel(g,new RectangleF(46,ry,626,82),i%2==0?Color.FromArgb(233,230,223):Color.FromArgb(218,214,206),6);
            Line(g,title[i],Body,Brushes.Black,new RectangleF(58,ry,182,82));
            Line(g,issue[i],Small,i==0?new SolidBrush(Color.FromArgb(54,92,57)):new SolidBrush(Red),new RectangleF(248,ry,150,82));
            Line(g,diag[i],Small,Brushes.Black,new RectangleF(408,ry+8,245,32));
            Line(g,"PLAYLIST  "+list[i],new Font("Arial",9,FontStyle.Bold),new SolidBrush(Color.FromArgb(94,75,32)),new RectangleF(408,ry+40,245,28));
        }
        Label(g,"SOMENTE LEITURA",487,1105,Gold);
    }

    static void DrawUsb(Graphics g, Image diag, Image backup, Image recovery, Image compatibility, float t)
    {
        Header(g,"04  KIT USB","CUIDE DO PENDRIVE ANTES DO SET.","Diagnóstico, backup, recuperação e compatibilidade com equipamento.",t/.8f);
        string[] labels = { "DIAGNÓSTICO", "CÓPIA SEGURA", "RECUPERAÇÃO", "COMPATIBILIDADE" };
        int index = Math.Min(3, (int)(t / 3.1f));
        float local = t - index * 3.1f;
        float p=Ease(local/.65f), y=260+(1-p)*80;
        UiPanel(g,new RectangleF(28,y,664,795),Color.FromArgb(190,186,178),22);
        UiField(g,"DISPOSITIVO EM ANÁLISE","E:\\  CRIVO-DEMO  •  FAT32  •  58,2 GB",new RectangleF(50,y+46,620,54));
        if(index==0){
            Stat(g,"PROBLEMAS","0",new RectangleF(50,y+135,185,110),Red); Stat(g,"ATENÇÃO","3",new RectangleF(245,y+135,185,110),Gold); Stat(g,"NÃO VERIFICADOS","0",new RectangleF(440,y+135,230,110),Ink);
            string[] a={"Sistema de arquivos","Biblioteca do Rekordbox","Dados de análise","Leitura dos áudios","Dados das tracks","Duplicatas"};
            string[] b={"FAT32 identificado","Biblioteca legível","728 arquivos localizados","728 tracks inspecionadas","12 dados incompletos","3 possíveis repetições"};
            for(int i=0;i<6;i++){float ry=y+275+i*70;UiPanel(g,new RectangleF(50,ry,620,60),i%2==0?Color.FromArgb(232,229,222):Color.FromArgb(218,214,206),5);Line(g,a[i],Body,Brushes.Black,new RectangleF(66,ry,245,60));Line(g,b[i],Small,Brushes.Black,new RectangleF(325,ry,325,60));}
        }else if(index==1){
            Line(g,"CÓPIA INTEGRAL VERIFICADA",H2,Brushes.Black,new RectangleF(54,y+135,590,42));
            UiField(g,"ONDE SALVAR","C:\\Music\\Backups\\CRIVO-DEMO",new RectangleF(50,y+215,620,56));
            Stat(g,"TRACKS","728",new RectangleF(50,y+305,190,112),Ink);Stat(g,"TAMANHO","18,4 GB",new RectangleF(250,y+305,190,112),Ink);Stat(g,"ESPAÇO","OK",new RectangleF(450,y+305,220,112),Color.FromArgb(54,92,57));
            string[] steps={"1  LISTAR TODOS OS ARQUIVOS","2  COPIAR SEM ALTERAR A ORIGEM","3  CONFERIR CADA ASSINATURA","4  GERAR RELATÓRIO"};
            for(int i=0;i<4;i++) Line(g,steps[i],H2,Brushes.Black,new RectangleF(68,y+455+i*58,560,48));
            UiButton(g,"CRIAR CÓPIA SEGURA",new RectangleF(410,y+705,240,54),true);
        }else if(index==2){
            Line(g,"RECUPERAÇÃO EM OUTRO LOCAL",H2,Brushes.Black,new RectangleF(54,y+135,590,42));
            Stat(g,"PLAYLISTS","14",new RectangleF(50,y+210,190,120),Ink);Stat(g,"LOCALIZADAS","721 / 728",new RectangleF(250,y+210,220,120),Gold);Stat(g,"ORIGEM","INTACTA",new RectangleF(480,y+210,190,120),Color.FromArgb(54,92,57));
            UiPanel(g,new RectangleF(50,y+370,620,240),Color.FromArgb(232,229,222),12);
            Line(g,"O QUE PODE SER RECUPERADO",Small,new SolidBrush(Color.FromArgb(72,68,62)),new RectangleF(70,y+390,560,30));
            Line(g,"Playlists e tracks ainda legíveis são reconstruídas em uma cópia separada.",H2,Brushes.Black,new RectangleF(70,y+430,555,78));
            Line(g,"Cues, loops, beatgrid ou waveform podem não ser recuperados.",Body,new SolidBrush(Red),new RectangleF(70,y+525,555,55));
            UiButton(g,"REVISAR RECUPERAÇÃO",new RectangleF(405,y+685,245,56),true);
        }else{
            Line(g,"COMPATIBILIDADE COM EQUIPAMENTO",H2,Brushes.Black,new RectangleF(54,y+135,590,42));
            UiField(g,"MODELO","Pioneer DJ CDJ-2000NXS2",new RectangleF(50,y+210,620,56));
            Stat(g,"RESULTADO","COMPATÍVEL",new RectangleF(50,y+300,620,118),Color.FromArgb(54,92,57));
            string[] req={"Sistema de arquivos","Biblioteca","Formatos de áudio","Taxa de amostragem","Integridade"};
            string[] val={"FAT32","EXPORT.PDB legível","MP3, WAV e AIFF","44,1 kHz e 48 kHz","Atenção: 3 duplicatas"};
            for(int i=0;i<5;i++){float ry=y+450+i*58;UiPanel(g,new RectangleF(50,ry,620,50),i%2==0?Color.FromArgb(232,229,222):Color.FromArgb(218,214,206),5);Line(g,req[i],Body,Brushes.Black,new RectangleF(66,ry,260,50));Line(g,val[i],Small,Brushes.Black,new RectangleF(340,ry,305,50));}
        }
        for (int i = 0; i < 4; i++)
        {
            var r = new RectangleF(31 + i * 168, 1070, 157, 46);
            FillRound(g, new SolidBrush(i == index ? Gold : Color.FromArgb(66, 63, 58)), r, 12);
            Line(g, labels[i], new Font("Arial", 8, FontStyle.Bold), i == index ? Brushes.Black : Brushes.White, r, StringAlignment.Center);
        }
        string detail = index == 0 ? "728 tracks verificadas" : index == 1 ? "origem preservada + cópia conferida" : index == 2 ? "recuperação sem gravar no original" : "requisitos oficiais por equipamento";
        Line(g, detail, H2, Brushes.White, new RectangleF(35, 1130, 650, 55), StringAlignment.Center);
    }

    static void DrawFinal(Graphics g, Image logo, float t)
    {
        float e = Ease(t / .7f);
        g.DrawImage(logo, 70, 135 - (1-e)*60, 105, 105);
        Line(g, "CRIVO DJ", Big, Brushes.White, new RectangleF(190, 130, 450, 90));
        Line(g, "PESQUISA MUSICAL EM UM SÓ FLUXO", H2, new SolidBrush(Gold), new RectangleF(70, 265, 580, 55), StringAlignment.Center);
        string[] cards = { "PORTÁTIL\nsem instalação", "CLARO\nantes de alterar", "SEGURO\nbackup e revisão", "COMPLETO\nlink ou pasta ao USB" };
        for (int i = 0; i < 4; i++)
        {
            float p = Ease((t - .18f*i) / .7f);
            float x = 46 + (i % 2) * 319, y = 385 + (i / 2) * 178 + (1-p)*45;
            var r = new RectangleF(x, y, 294, 145);
            FillRound(g, new SolidBrush(i == 3 ? Gold : Paper), r, 22);
            Line(g, cards[i].Split('\n')[0], H2, Brushes.Black, new RectangleF(x, y+24, 294, 43), StringAlignment.Center);
            Line(g, cards[i].Split('\n')[1], Body, Brushes.Black, new RectangleF(x, y+68, 294, 40), StringAlignment.Center);
        }
        using (var p = new Pen(Gold, 4)) g.DrawLine(p, 84, 805, 636, 805);
        Line(g, "BAIXE  •  ORGANIZE  •  REKORDBOX  •  AUDITE  •  USB", new Font("Arial", 16, FontStyle.Bold), Brushes.White, new RectangleF(25, 830, 670, 60), StringAlignment.Center);
        Label(g, "WINDOWS", 139, 935, Gold); Label(g, "BETA FECHADO", 303, 935, Paper); Label(g, "MANELZ0RD", 485, 935, Gold);
        Line(g, "CRIVO DJ", H1, Brushes.White, new RectangleF(40, 1060, 640, 60), StringAlignment.Center);
    }

    public static int Main(string[] args)
    {
        if (args.Length < 3) { Console.Error.WriteLine("uso: ReelRenderer <screenshots> <logo> <frames>"); return 2; }
        string shots = args[0], logoPath = args[1], output = args[2]; Directory.CreateDirectory(output);
        using (var logo = Image.FromFile(logoPath))
        using (var download = Image.FromFile(Path.Combine(shots, "01-baixar-tracks.png")))
        using (var organize = Image.FromFile(Path.Combine(shots, "02-organizar-biblioteca.png")))
        using (var audit = Image.FromFile(Path.Combine(shots, "03-auditoria-rekordbox.png")))
        using (var diag = Image.FromFile(Path.Combine(shots, "04-kit-usb-diagnostico.png")))
        using (var backup = Image.FromFile(Path.Combine(shots, "05-kit-usb-copia-segura.png")))
        using (var recovery = Image.FromFile(Path.Combine(shots, "06-kit-usb-recuperacao.png")))
        using (var compatibility = Image.FromFile(Path.Combine(shots, "07-kit-usb-compatibilidade.png")))
        {
            for (int frame = 0; frame < Seconds * Fps; frame++)
            {
                float time = frame / (float)Fps;
                using (var bmp = new Bitmap(W, H, PixelFormat.Format24bppRgb))
                using (var g = Graphics.FromImage(bmp))
                {
                    g.SmoothingMode = SmoothingMode.AntiAlias; g.InterpolationMode = InterpolationMode.HighQualityBicubic; g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                    Background(g, time);
                    if (time < 4f) DrawIntro(g, logo, time);
                    else if (time < 12f) DrawDownload(g, download, time - 4f);
                    else if (time < 22f) DrawOrganize(g, organize, time - 12f);
                    else if (time < 31f) DrawAudit(g, audit, time - 22f);
                    else if (time < 44f) DrawUsb(g, diag, backup, recovery, compatibility, time - 31f);
                    else DrawFinal(g, logo, time - 44f);
                    bmp.Save(Path.Combine(output, string.Format("frame-{0:D5}.jpg", frame)), ImageFormat.Jpeg);
                }
                if (frame % 120 == 0) Console.WriteLine("frame " + frame);
            }
        }
        return 0;
    }
}
