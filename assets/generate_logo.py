#!/usr/bin/env python3
"""
generate_logo.py - Générateur de logos 3D isométriques pour agent-ws.

Composition épurée :
- Grand cube hôte 3D en filaire subtil (sans points aux intersections, ne masque pas la scène)
- Cube 'home' (session utilisateur au premier plan à gauche, hauteur basse)
- Cube 'A-WS' (session agent IA au premier plan à droite, hauteur haute)
- Un PIPE DROIT et unicolore qui arrive directement sur la face visible de A-WS
"""

import math
import subprocess
import os
import sys
import argparse

def project_iso(x, y, z, cx=512, cy=512, scale=3.6):
    """Projection isométrique 3D -> 2D (angle standard 30°)."""
    angle = math.radians(30)
    cos_a = math.cos(angle)
    sin_a = math.sin(angle)
    px = cx + (x - y) * cos_a * scale
    py = cy + (x + y) * sin_a * scale - z * scale
    return (round(px, 2), round(py, 2))

def render_logo(output_svg, variant="sober_mono", pipe_style="straight", pipe_color=None,
                icon_only=False, transparent_bg=False):
    width = 1024
    height = 1024
    cx = 512
    cy = 515 if icon_only else 485
    scale = 3.6 if icon_only else 3.3
    L = 100
    
    # 2 Cubes
    s_cube = 30
    hx, hy, hz = 14, 56, 14
    home_pos = (hx, hy, hz)
    
    ax, ay, az = 56, 14, 54
    aws_pos = (ax, ay, az)
    
    themes = {
        "sober_mono": {
            "bg": "#0A0B0E" if not transparent_bg else "none",
            "outer_stroke": "rgba(148, 163, 184, 0.28)",
            "outer_back_stroke": "rgba(148, 163, 184, 0.10)",
            "outer_fill_top": "rgba(255, 255, 255, 0.02)",
            "outer_fill_left": "rgba(255, 255, 255, 0.01)",
            "outer_fill_right": "rgba(0, 0, 0, 0.15)",
            "home_top": "#64748B", "home_right": "#475569", "home_left": "#334155", "home_stroke": "#CBD5E1", "home_text": "#F8FAFC",
            "aws_top": "#FFFFFF", "aws_right": "#CBD5E1", "aws_left": "#94A3B8", "aws_stroke": "#FFFFFF", "aws_text": "#0F172A",
            "pipe_col": "#FFFFFF",
            "title_col": "#FFFFFF", "sub_col": "rgba(255, 255, 255, 0.45)"
        },
        "modern_cyan": {
            "bg": "#0B0E14" if not transparent_bg else "none",
            "outer_stroke": "rgba(0, 229, 255, 0.25)",
            "outer_back_stroke": "rgba(0, 229, 255, 0.08)",
            "outer_fill_top": "rgba(0, 229, 255, 0.03)",
            "outer_fill_left": "rgba(15, 25, 45, 0.20)",
            "outer_fill_right": "rgba(10, 18, 35, 0.25)",
            "home_top": "#FFA726", "home_right": "#FB8C00", "home_left": "#F57C00", "home_stroke": "#FFF3E0", "home_text": "#1F1203",
            "aws_top": "#00E5FF", "aws_right": "#00B0FF", "aws_left": "#0288D1", "aws_stroke": "#E0F7FA", "aws_text": "#031B2A",
            "pipe_col": "#00E5FF",
            "title_col": "#FFFFFF", "sub_col": "rgba(255, 255, 255, 0.45)"
        },
        "cyber_emerald": {
            "bg": "#090D10" if not transparent_bg else "none",
            "outer_stroke": "rgba(16, 185, 129, 0.25)",
            "outer_back_stroke": "rgba(16, 185, 129, 0.08)",
            "outer_fill_top": "rgba(16, 185, 129, 0.03)",
            "outer_fill_left": "rgba(5, 30, 25, 0.20)",
            "outer_fill_right": "rgba(2, 20, 18, 0.25)",
            "home_top": "#818CF8", "home_right": "#6366F1", "home_left": "#4F46E5", "home_stroke": "#E0E7FF", "home_text": "#1E1B4B",
            "aws_top": "#10B981", "aws_right": "#059669", "aws_left": "#047857", "aws_stroke": "#D1FAE5", "aws_text": "#022C22",
            "pipe_col": "#10B981",
            "title_col": "#FFFFFF", "sub_col": "rgba(255, 255, 255, 0.45)"
        }
    }
    pal = themes.get(variant, themes["sober_mono"])
    chosen_pipe_col = pipe_color if pipe_color else pal["pipe_col"]
    
    svg = []
    svg.append(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}">')
    svg.append('<defs>')
    svg.append('''
      <filter id="cube-shadow" x="-20%" y="-20%" width="140%" height="140%">
        <feDropShadow dx="0" dy="12" stdDeviation="16" flood-color="#000000" flood-opacity="0.8"/>
      </filter>
      <filter id="pipe-shadow" x="-30%" y="-30%" width="160%" height="160%">
        <feDropShadow dx="0" dy="8" stdDeviation="10" flood-color="#000000" flood-opacity="0.65"/>
      </filter>
    ''')
    svg.append('</defs>')
    
    if pal["bg"] != "none":
        svg.append(f'<rect width="{width}" height="{height}" fill="{pal["bg"]}" rx="48"/>')
        
    pts = {
        'O': project_iso(0, 0, 0, cx, cy, scale),
        'X': project_iso(L, 0, 0, cx, cy, scale),
        'Y': project_iso(0, L, 0, cx, cy, scale),
        'XY': project_iso(L, L, 0, cx, cy, scale),
        'Z': project_iso(0, 0, L, cx, cy, scale),
        'XZ': project_iso(L, 0, L, cx, cy, scale),
        'YZ': project_iso(0, L, L, cx, cy, scale),
        'XYZ': project_iso(L, L, L, cx, cy, scale),
    }
    
    # 1. Arêtes arrières du grand cube hôte
    for p1, p2 in [('O', 'X'), ('O', 'Y'), ('O', 'Z')]:
        svg.append(f'<line x1="{pts[p1][0]}" y1="{pts[p1][1]}" x2="{pts[p2][0]}" y2="{pts[p2][1]}" stroke="{pal["outer_back_stroke"]}" stroke-width="1.8" stroke-dasharray="4,6"/>')

    # 2. Grand cube hôte (structure et faces, tracé en filaire doux sans points pour ne pas gêner la lisibilité)
    p_top = f"{pts['Z'][0]},{pts['Z'][1]} {pts['XZ'][0]},{pts['XZ'][1]} {pts['XYZ'][0]},{pts['XYZ'][1]} {pts['YZ'][0]},{pts['YZ'][1]}"
    svg.append(f'<polygon points="{p_top}" fill="{pal["outer_fill_top"]}" stroke="none"/>')
    p_fl = f"{pts['Y'][0]},{pts['Y'][1]} {pts['XY'][0]},{pts['XY'][1]} {pts['XYZ'][0]},{pts['XYZ'][1]} {pts['YZ'][0]},{pts['YZ'][1]}"
    svg.append(f'<polygon points="{p_fl}" fill="{pal["outer_fill_left"]}" stroke="none"/>')
    p_fr = f"{pts['X'][0]},{pts['X'][1]} {pts['XY'][0]},{pts['XY'][1]} {pts['XYZ'][0]},{pts['XYZ'][1]} {pts['XZ'][0]},{pts['XZ'][1]}"
    svg.append(f'<polygon points="{p_fr}" fill="{pal["outer_fill_right"]}" stroke="none"/>')

    outer_lines = [
        ('Z', 'XZ'), ('XZ', 'X'), ('X', 'XY'),
        ('XY', 'Y'), ('Y', 'YZ'), ('YZ', 'Z'),
        ('XYZ', 'XZ'), ('XYZ', 'YZ'), ('XYZ', 'XY')
    ]
    for p1, p2 in outer_lines:
        svg.append(f'<line x1="{pts[p1][0]}" y1="{pts[p1][1]}" x2="{pts[p2][0]}" y2="{pts[p2][1]}" stroke="{pal["outer_stroke"]}" stroke-width="1.8" stroke-linecap="round"/>')

    # FONCTION DE RENDU D'UN CUBE SOLIDE
    def render_cube(origin, size, label, col_top, col_right, col_left, stroke_col, text_col=None):
        ox, oy, oz = origin
        sz = size
        
        v000 = project_iso(ox, oy, oz, cx, cy, scale)
        v100 = project_iso(ox + sz, oy, oz, cx, cy, scale)
        v010 = project_iso(ox, oy + sz, oz, cx, cy, scale)
        v110 = project_iso(ox + sz, oy + sz, oz, cx, cy, scale)
        v001 = project_iso(ox, oy, oz + sz, cx, cy, scale)
        v101 = project_iso(ox + sz, oy, oz + sz, cx, cy, scale)
        v011 = project_iso(ox, oy + sz, oz + sz, cx, cy, scale)
        v111 = project_iso(ox + sz, oy + sz, oz + sz, cx, cy, scale)
        
        svg.append('<g filter="url(#cube-shadow)">')
        pl = f"{v010[0]},{v010[1]} {v110[0]},{v110[1]} {v111[0]},{v111[1]} {v011[0]},{v011[1]}"
        svg.append(f'<polygon points="{pl}" fill="{col_left}" stroke="{stroke_col}" stroke-width="2.5" stroke-linejoin="round"/>')
        pr = f"{v100[0]},{v100[1]} {v110[0]},{v110[1]} {v111[0]},{v111[1]} {v101[0]},{v101[1]}"
        svg.append(f'<polygon points="{pr}" fill="{col_right}" stroke="{stroke_col}" stroke-width="2.5" stroke-linejoin="round"/>')
        pt = f"{v001[0]},{v001[1]} {v101[0]},{v101[1]} {v111[0]},{v111[1]} {v011[0]},{v011[1]}"
        svg.append(f'<polygon points="{pt}" fill="{col_top}" stroke="{stroke_col}" stroke-width="2.5" stroke-linejoin="round"/>')
        
        if label and text_col:
            tc_x = (v001[0] + v101[0] + v111[0] + v011[0]) / 4
            tc_y = (v001[1] + v101[1] + v111[1] + v011[1]) / 4
            font_size = "24" if len(label) <= 4 else "20"
            svg.append(f'''
            <g transform="matrix(0.866025, 0.5, -0.866025, 0.5, {tc_x}, {tc_y})">
              <text x="0" y="0" font-family="'JetBrains Mono', 'Fira Code', monospace" 
                    font-size="{font_size}" font-weight="900" fill="{text_col}" text-anchor="middle" dominant-baseline="central">{label}</text>
            </g>
            ''')
        svg.append('</g>')

    # 3. Dessiner le cube A-WS
    render_cube(aws_pos, s_cube, "A-WS",
                pal["aws_top"], pal["aws_right"], pal["aws_left"],
                pal["aws_stroke"], pal["aws_text"])

    # 4. PIPE UNICOLORE DROIT (entrant directement sur la face visible de A-WS)
    pipe_w = 17.0 * (scale / 3.6)
    
    if pipe_style == "straight":
        # Départ derrière l'angle haut droit de home (43, 57, 43)
        # Arrivée au centre de la face visible gauche de A-WS (y = ay + s_cube)
        p1 = (hx + s_cube - 1, hy + 1, hz + s_cube - 1)
        p2 = (ax + s_cube / 2, ay + s_cube, az + s_cube / 2)
        
        s1 = project_iso(p1[0], p1[1], p1[2], cx, cy, scale)
        s2 = project_iso(p2[0], p2[1], p2[2], cx, cy, scale)
        
        svg.append('<g filter="url(#pipe-shadow)">')
        svg.append(f'<line x1="{s1[0]}" y1="{s1[1]}" x2="{s2[0]}" y2="{s2[1]}" stroke="{chosen_pipe_col}" stroke-width="{pipe_w:.1f}" stroke-linecap="round"/>')
        svg.append('</g>')
        
    else:
        # Variante coudée optionnelle
        p0 = (hx + s_cube - 5, hy + 5, hz + s_cube)
        p1 = (hx + s_cube - 5, hy + 5, az + s_cube/2)
        p2 = (ax, ay + s_cube/2, az + s_cube/2)
        s0 = project_iso(p0[0], p0[1], p0[2], cx, cy, scale)
        s1 = project_iso(p1[0], p1[1], p1[2], cx, cy, scale)
        s2 = project_iso(p2[0], p2[1], p2[2], cx, cy, scale)
        path_d = f"M {s0[0]} {s0[1]} L {s1[0]} {s1[1]} L {s2[0]} {s2[1]}"
        svg.append('<g filter="url(#pipe-shadow)">')
        svg.append(f'<path d="{path_d}" fill="none" stroke="{chosen_pipe_col}" stroke-width="{pipe_w:.1f}" stroke-linecap="round" stroke-linejoin="round"/>')
        svg.append('</g>')

    # 5. Dessiner le cube home au premier plan
    render_cube(home_pos, s_cube, "home",
                pal["home_top"], pal["home_right"], pal["home_left"],
                pal["home_stroke"], pal["home_text"])

    if not icon_only:
        svg.append(f'''
        <text x="512" y="930" font-family="'Inter', 'Segoe UI', system-ui, sans-serif" 
              font-size="36" font-weight="800" fill="{pal['title_col']}" text-anchor="middle" letter-spacing="8">AGENT-WS</text>
        <text x="512" y="965" font-family="'Inter', 'Segoe UI', system-ui, sans-serif" 
              font-size="16" font-weight="500" fill="{pal['sub_col']}" text-anchor="middle" letter-spacing="4">ISOLATED LINUX AI WORKSPACE</text>
        ''')

    svg.append('</svg>')
    
    content = "\n".join(svg)
    with open(output_svg, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"✓ SVG généré : {output_svg}")

def convert_to_png(svg_path, png_path, size=1024):
    cmd = ["rsvg-convert", "-w", str(size), "-h", str(size), svg_path, "-o", png_path]
    subprocess.run(cmd, check=True)
    print(f"✓ PNG exporté ({size}x{size}) : {png_path}")

def main():
    default_dir = os.path.dirname(os.path.abspath(__file__))
    parser = argparse.ArgumentParser(description="Générateur de logos 3D agent-ws épuré")
    parser.add_argument("--out-dir", default=default_dir, help="Dossier de sortie des logos (défaut: dossier du script)")
    parser.add_argument("--variant", default="sober_mono", choices=["all", "sober_mono", "modern_cyan", "cyber_emerald"], help="Variante de couleur")
    parser.add_argument("--pipe-style", default="straight", choices=["straight", "elbow"], help="Style du pipe (straight ou elbow)")
    parser.add_argument("--pipe-color", default=None, help="Couleur spécifique du pipe (ex: #FFFFFF)")
    parser.add_argument("--icon-only", action="store_true", default=True, help="Génère l'icône seule sans titre")
    parser.add_argument("--with-title", action="store_true", help="Génère la version bannière avec titre")
    parser.add_argument("--transparent", action="store_true", help="Fond transparent")
    parser.add_argument("--all-variants", action="store_true", help="Génère toutes les déclinaisons standards")
    args = parser.parse_args()
    
    if args.with_title:
        args.icon_only = False
    
    os.makedirs(args.out_dir, exist_ok=True)
    
    if args.all_variants:
        configurations = [
            ("sober_mono", False, False, ""),
            ("sober_mono", True, False, "_icon"),
            ("sober_mono", False, True, "_transparent"),
            ("sober_mono", True, True, "_icon_transparent"),
            ("modern_cyan", False, False, ""),
            ("modern_cyan", True, False, "_icon"),
            ("modern_cyan", False, True, "_transparent"),
            ("modern_cyan", True, True, "_icon_transparent"),
            ("cyber_emerald", False, False, ""),
            ("cyber_emerald", True, False, "_icon"),
        ]
        for var, ico, trans, sfx in configurations:
            svg_file = os.path.join(args.out_dir, f"logo_{var}{sfx}.svg")
            png_file = os.path.join(args.out_dir, f"logo_{var}{sfx}.png")
            render_logo(svg_file, variant=var, pipe_style=args.pipe_style, pipe_color=args.pipe_color,
                        icon_only=ico, transparent_bg=trans)
            convert_to_png(svg_file, png_file, size=1024)
        return
        
    variants = ["sober_mono", "modern_cyan", "cyber_emerald"] if args.variant == "all" else [args.variant]
    for v in variants:
        prefix = f"logo_{v}"
        if args.icon_only:
            prefix += "_icon"
        if args.transparent:
            prefix += "_transparent"
        if args.pipe_style != "straight":
            prefix += f"_{args.pipe_style}"
            
        svg_file = os.path.join(args.out_dir, f"{prefix}.svg")
        png_file = os.path.join(args.out_dir, f"{prefix}.png")
        
        render_logo(svg_file, variant=v, pipe_style=args.pipe_style, pipe_color=args.pipe_color,
                    icon_only=args.icon_only, transparent_bg=args.transparent)
        convert_to_png(svg_file, png_file, size=1024)

if __name__ == "__main__":
    main()
