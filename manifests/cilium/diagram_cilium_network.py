#!/usr/bin/env python3
"""
Мережева діаграма k3s кластера після міграції на Cilium.
Генерує PDF: manifests/cilium/K3S_CILIUM_NETWORK_DIAGRAM.pdf

Запуск: python diagram_cilium_network.py
Залежності: pip install matplotlib (або: python -m venv .venv && source .venv/bin/activate && pip install matplotlib)
"""

import os
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
import matplotlib.lines as mlines

# Розміри та кольори
FIG_SIZE = (14, 10)
BG_COLOR = "#f8f9fa"
NODE_COLOR = "#e3f2fd"
NODE_BORDER = "#1976d2"
CILIUM_COLOR = "#00d4aa"
CILIUM_BORDER = "#00897b"
WG_COLOR = "#fff3e0"
WG_BORDER = "#e65100"
TEXT_COLOR = "#212121"
FONT_SIZE = 9
TITLE_SIZE = 14


def draw_node(ax, x, y, w, h, label, details, color=NODE_COLOR, border=NODE_BORDER):
    """Малює прямокутник ноди з текстом."""
    box = FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02", 
                         facecolor=color, edgecolor=border, linewidth=2)
    ax.add_patch(box)
    ax.text(x + w/2, y + h - 0.35, label, ha='center', va='top', fontsize=FONT_SIZE+1, fontweight='bold')
    for i, line in enumerate(details):
        ax.text(x + w/2, y + h - 0.6 - i*0.25, line, ha='center', va='top', fontsize=FONT_SIZE)


def draw_arrow(ax, start, end, color='#666', dashed=False):
    """Малює стрілку між точками."""
    ls = '--' if dashed else '-'
    ax.annotate('', xy=end, xytext=start,
                arrowprops=dict(arrowstyle='->', color=color, lw=1.5, linestyle=ls))


def main():
    fig, ax = plt.subplots(1, 1, figsize=FIG_SIZE, facecolor=BG_COLOR)
    ax.set_facecolor(BG_COLOR)
    ax.set_xlim(0, 14)
    ax.set_ylim(0, 10)
    ax.axis('off')

    # Заголовок
    ax.text(7, 9.5, 'k3s кластер після міграції на Cilium', 
            ha='center', fontsize=TITLE_SIZE, fontweight='bold', color=TEXT_COLOR)
    ax.text(7, 9.0, 'Native routing • eBPF • Hubble • Pod CIDR 10.42.0.0/16 • Service CIDR 10.43.0.0/16',
            ha='center', fontsize=FONT_SIZE, color='#555')

    # === Локація OCI (Amper) - зліва ===
    ax.add_patch(mpatches.FancyBboxPatch((0.3, 4.5), 4.2, 4.2, boxstyle="round,pad=0.05",
                                         facecolor='#e8f5e9', edgecolor='#2e7d32', linewidth=1.5, alpha=0.7))
    ax.text(2.4, 8.5, 'OCI (Amper)', ha='center', fontsize=FONT_SIZE+1, fontweight='bold', color='#1b5e20')
    ax.text(2.4, 8.1, '10.0.10.0/24', ha='center', fontsize=FONT_SIZE-1, color='#555')

    draw_node(ax, 0.6, 6.0, 1.8, 1.8, 'master-node', 
              ['control-plane, etcd', '10.0.10.10', 'Cilium agent', 'Hubble'])
    draw_node(ax, 2.4, 4.8, 1.8, 1.8, 'work-node', 
              ['worker', '10.0.10.20', 'Cilium agent', 'Hubble'])

    # === Локація VRN625 - центр ===
    ax.add_patch(mpatches.FancyBboxPatch((4.8, 4.5), 4.2, 4.2, boxstyle="round,pad=0.05",
                                         facecolor='#e3f2fd', edgecolor='#1565c0', linewidth=1.5, alpha=0.7))
    ax.text(6.9, 8.5, 'VRN625', ha='center', fontsize=FONT_SIZE+1, fontweight='bold', color='#0d47a1')
    ax.text(6.9, 8.1, '192.168.2.0/24', ha='center', fontsize=FONT_SIZE-1, color='#555')

    draw_node(ax, 5.4, 6.0, 1.8, 1.8, 'macmini7', 
              ['control-plane, etcd', '192.168.2.19', 'Cilium agent', 'Hubble'])

    # === Локація Syhiv17 - справа ===
    ax.add_patch(mpatches.FancyBboxPatch((9.3, 4.5), 4.2, 4.2, boxstyle="round,pad=0.05",
                                         facecolor='#fce4ec', edgecolor='#c2185b', linewidth=1.5, alpha=0.7))
    ax.text(11.4, 8.5, 'Syhiv17', ha='center', fontsize=FONT_SIZE+1, fontweight='bold', color='#880e4f')
    ax.text(11.4, 8.1, '192.168.1.0/24', ha='center', fontsize=FONT_SIZE-1, color='#555')

    draw_node(ax, 10.2, 6.0, 1.8, 1.8, 'beelinkeqr5', 
              ['control-plane, etcd', '192.168.1.19', 'Cilium agent', 'Hubble'])

    # === WireGuard тунелі (пунктир) ===
    ax.text(7, 4.2, 'WireGuard (wg0, wg1): 192.168.100.0/30, 192.168.200.0/30', 
            ha='center', fontsize=FONT_SIZE-1, color='#e65100', style='italic')
    draw_arrow(ax, (2.4, 6.5), (5.2, 6.5), color='#e65100', dashed=True)
    draw_arrow(ax, (6.9, 6.5), (9.0, 6.5), color='#e65100', dashed=True)
    draw_arrow(ax, (2.4, 5.5), (5.2, 5.5), color='#e65100', dashed=True)

    # === Cilium Data Plane (знизу) ===
    ax.add_patch(mpatches.FancyBboxPatch((2, 0.2), 10, 2.2, boxstyle="round,pad=0.08",
                                         facecolor=CILIUM_COLOR, edgecolor=CILIUM_BORDER, linewidth=2, alpha=0.9))
    ax.text(7, 2.1, 'Cilium CNI (eBPF)', ha='center', fontsize=FONT_SIZE+1, fontweight='bold', color='#004d40')
    ax.text(7, 1.7, 'Native routing (без VXLAN) • kube-proxy replacement • autoDirectNodeRoutes', 
            ha='center', fontsize=FONT_SIZE-1, color='#00695c')
    ax.text(7, 1.3, 'Pod CIDR: 10.42.0.0/16 (по ноді /24) • Service: 10.43.0.0/16 • nonMasquerade: Pod, Service, Node мережі',
            ha='center', fontsize=FONT_SIZE-1, color='#00695c')
    ax.text(7, 0.7, 'Hubble: flow, DNS, HTTP, drop • Gateway API • Traefik Ingress',
            ha='center', fontsize=FONT_SIZE-1, color='#00695c')

    # Стрілки від нод до Cilium
    for x in [1.5, 3.3, 6.3, 11.1]:
        draw_arrow(ax, (x, 5.9), (x, 2.5), color=CILIUM_BORDER)

    # Легенда
    legend_elements = [
        mpatches.Patch(facecolor=NODE_COLOR, edgecolor=NODE_BORDER, label='Kubernetes Node'),
        mpatches.Patch(facecolor=CILIUM_COLOR, edgecolor=CILIUM_BORDER, label='Cilium eBPF'),
    ]
    ax.legend(handles=legend_elements, loc='upper left', fontsize=FONT_SIZE-1)

    plt.tight_layout()
    out_path = os.path.join(os.path.dirname(__file__), 'K3S_CILIUM_NETWORK_DIAGRAM.pdf')
    fig.savefig(out_path, format='pdf', bbox_inches='tight', facecolor=BG_COLOR, dpi=150)
    plt.close()
    print(f'Збережено: {out_path}')


if __name__ == '__main__':
    main()
