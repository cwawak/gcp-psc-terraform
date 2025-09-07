#!/usr/bin/env python3
"""
Confluent Endpoints with Proper Scrollable Interface using curses
"""

import json
import subprocess
import time
import curses
from collections import Counter
from datetime import datetime

def get_endpoints():
    try:
        result = subprocess.run([
            "confluent", "network", "access-point", "private-link", 
            "egress-endpoint", "list", "--output", "json"
        ], capture_output=True, text=True, check=True)
        return json.loads(result.stdout)
    except:
        return []

class EndpointViewer:
    def __init__(self, stdscr):
        self.stdscr = stdscr
        self.endpoints = []
        self.current_row = 0
        self.scroll_offset = 0
        self.auto_refresh = False
        self.refresh_interval = 15
        self.last_refresh_time = time.time()
        self.last_data_update_time = time.time()  # Separate time for actual data updates
        
        # Initialize colors
        curses.start_color()
        curses.init_pair(1, curses.COLOR_CYAN, curses.COLOR_BLACK)     # Names/IPs
        curses.init_pair(2, curses.COLOR_WHITE, curses.COLOR_BLACK)    # IDs
        curses.init_pair(3, curses.COLOR_YELLOW, curses.COLOR_BLACK)   # Pending
        curses.init_pair(4, curses.COLOR_GREEN, curses.COLOR_BLACK)    # Ready/Success
        curses.init_pair(5, curses.COLOR_RED, curses.COLOR_BLACK)      # Failed
        curses.init_pair(6, curses.COLOR_BLUE, curses.COLOR_BLACK)     # Processing
        curses.init_pair(7, curses.COLOR_MAGENTA, curses.COLOR_BLACK)  # Headers
        
        # Colors
        self.CYAN = curses.color_pair(1)
        self.WHITE = curses.color_pair(2)
        self.YELLOW = curses.color_pair(3)
        self.GREEN = curses.color_pair(4)
        self.RED = curses.color_pair(5)
        self.BLUE = curses.color_pair(6)
        self.MAGENTA = curses.color_pair(7)
        
        # Setup screen
        curses.curs_set(0)  # Hide cursor
        self.stdscr.keypad(True)  # Enable special keys
        self.stdscr.timeout(1000)  # 1 second timeout for getch
        
        # Load initial data
        self.load_data()
    
    def load_data(self):
        """Load endpoint data"""
        self.endpoints = get_endpoints()
        if self.endpoints:
            self.endpoints.sort(key=lambda x: int(x['name'].split('-')[1]) if '-' in x['name'] else 999)
        self.last_data_update_time = time.time()
    
    def get_status_color(self, status):
        """Get color for status"""
        colors = {
            'PENDING_ACCEPT': self.YELLOW,
            'READY': self.GREEN,
            'FAILED': self.RED,
            'PROVISIONING': self.BLUE
        }
        return colors.get(status, self.WHITE)
    
    def draw_header(self, height, width):
        """Draw header with status summary"""
        if not self.endpoints:
            return 4
        
        status_counts = Counter(ep.get('phase', 'UNKNOWN') for ep in self.endpoints)
        current_time = datetime.fromtimestamp(self.last_data_update_time).strftime("%H:%M:%S")
        
        # Main header
        header_text = f"🌐 CONFLUENT ENDPOINTS ({len(self.endpoints)} Total)"
        self.stdscr.addstr(0, (width - len(header_text)) // 2, header_text, self.CYAN | curses.A_BOLD)
        
        # Last updated time
        time_text = f"🕐 Last Updated: {current_time}"
        self.stdscr.addstr(1, (width - len(time_text)) // 2, time_text, self.WHITE)
        
        # Status breakdown
        status_icons = {'PENDING_ACCEPT': '⏳', 'READY': '✅', 'FAILED': '❌', 'PROVISIONING': '🔄'}
        
        y = 3
        for status, count in status_counts.items():
            icon = status_icons.get(status, '❓')
            color = self.get_status_color(status)
            bar_length = min(20, count // 3)
            bar = "█" * bar_length
            
            status_line = f"{icon} {status:<15} {count:>3} {bar}"
            if y < height - 1:
                self.stdscr.addstr(y, 2, status_line, color)
            y += 1
        
        return y + 1
    
    def draw_table(self, start_y, height, width):
        """Draw the scrollable endpoint table"""
        if not self.endpoints:
            self.stdscr.addstr(start_y, 2, "No endpoints found", self.RED)
            return
        
        # Calculate column widths based on terminal width
        name_width = 12
        id_width = 15
        status_width = 18
        ip_width = 16
        # Connection ID gets remaining width
        conn_id_width = max(20, width - name_width - id_width - status_width - ip_width - 8)  # -8 for spacing
        
        # Table header with dynamic widths
        header = f"{'Name':<{name_width}} {'ID':<{id_width}} {'Status':<{status_width}} {'IP Address':<{ip_width}} {'Connection ID':<{conn_id_width}}"
        if start_y < height - 1:
            self.stdscr.addstr(start_y, 0, header[:width-1], self.WHITE | curses.A_BOLD)
            self.stdscr.addstr(start_y + 1, 0, "─" * (width - 1), self.CYAN)
        
        # Calculate visible area for table
        table_start_y = start_y + 2
        visible_rows = height - table_start_y - 3  # Leave space for footer
        
        # Draw endpoints
        for i in range(visible_rows):
            row_index = self.scroll_offset + i
            if row_index >= len(self.endpoints):
                break
            
            y = table_start_y + i
            if y >= height - 3:
                break
                
            ep = self.endpoints[row_index]
            name = ep.get('name', '')
            ep_id = ep.get('id', '')[:id_width-1]
            status = ep.get('phase', 'UNKNOWN')
            ip = ep.get('gcp_private_service_connect_endpoint_ip_address', '')
            conn_id = ep.get('gcp_private_service_connect_endpoint_connection_id', '')[:conn_id_width-1]
            
            # Highlight current row
            attr = curses.A_REVERSE if row_index == self.current_row else 0
            
            # Status with icon
            status_icons = {'PENDING_ACCEPT': '⏳', 'READY': '✅', 'FAILED': '❌', 'PROVISIONING': '🔄'}
            status_icon = status_icons.get(status, '❓')
            status_color = self.get_status_color(status)
            
            # Calculate column positions
            name_pos = 0
            id_pos = name_width + 1
            status_pos = id_pos + id_width + 1
            ip_pos = status_pos + status_width + 1
            conn_pos = ip_pos + ip_width + 1
            
            # Draw row with dynamic positioning and widths
            try:
                self.stdscr.addstr(y, name_pos, f"{name:<{name_width}}", self.CYAN | attr)
                self.stdscr.addstr(y, id_pos, f"{ep_id:<{id_width}}", self.WHITE | attr)
                self.stdscr.addstr(y, status_pos, f"{status_icon} {status:<{status_width-3}}", status_color | attr)
                self.stdscr.addstr(y, ip_pos, f"{ip:<{ip_width}}", self.CYAN | attr)
                if conn_pos < width - 1:
                    self.stdscr.addstr(y, conn_pos, f"{conn_id:<{conn_id_width}}"[:width-conn_pos-1], self.WHITE | attr)
            except curses.error:
                pass  # Handle case where terminal is too small
    
    def draw_footer(self, height, width):
        """Draw footer with controls and countdown"""
        if height < 3:
            return
            
        footer_y = height - 2
        
        # Auto-refresh status with countdown
        if self.auto_refresh:
            time_until_refresh = self.refresh_interval - (time.time() - self.last_refresh_time)
            if time_until_refresh > 0:
                refresh_text = f"Auto-refresh: ON - Next in ⏱️ {int(time_until_refresh)}s"
                color = self.GREEN
            else:
                refresh_text = "Auto-refresh: ON - Refreshing..."
                color = self.YELLOW
        else:
            refresh_text = "Auto-refresh: OFF"
            color = self.RED
        
        # Controls
        controls = "Controls: [r]Refresh [t]Toggle [↑↓]Navigate [PgUp/PgDn]Scroll [q]Quit"
        
        try:
            self.stdscr.addstr(footer_y - 1, 0, "─" * (width - 1), self.CYAN)
            self.stdscr.addstr(footer_y, 0, refresh_text, color)
            self.stdscr.addstr(footer_y + 1, 0, controls, self.WHITE)
        except curses.error:
            pass
    
    def handle_scroll(self):
        """Handle scrolling logic"""
        max_scroll = max(0, len(self.endpoints) - 1)
        
        # Adjust scroll offset to keep current row visible
        height, width = self.stdscr.getmaxyx()
        visible_rows = height - 10  # Approximate visible rows
        
        if self.current_row < self.scroll_offset:
            self.scroll_offset = self.current_row
        elif self.current_row >= self.scroll_offset + visible_rows:
            self.scroll_offset = self.current_row - visible_rows + 1
            
        self.scroll_offset = max(0, min(self.scroll_offset, max_scroll))
    
    def run(self):
        """Main run loop"""
        while True:
            height, width = self.stdscr.getmaxyx()
            
            # Handle auto-refresh
            if self.auto_refresh and (time.time() - self.last_refresh_time) >= self.refresh_interval:
                self.load_data()
                self.last_refresh_time = time.time()
            
            # Clear and redraw
            self.stdscr.clear()
            
            # Draw components
            header_end = self.draw_header(height, width)
            self.draw_table(header_end, height, width)
            self.draw_footer(height, width)
            
            self.stdscr.refresh()
            
            # Get input
            key = self.stdscr.getch()
            
            if key == ord('q'):
                break
            elif key == ord('r'):
                self.load_data()
                self.last_refresh_time = time.time()
            elif key == ord('t'):
                self.auto_refresh = not self.auto_refresh
                if self.auto_refresh:
                    self.last_refresh_time = time.time()
            elif key == curses.KEY_UP and self.current_row > 0:
                self.current_row -= 1
                self.handle_scroll()
            elif key == curses.KEY_DOWN and self.current_row < len(self.endpoints) - 1:
                self.current_row += 1
                self.handle_scroll()
            elif key == curses.KEY_PPAGE:  # Page Up
                self.current_row = max(0, self.current_row - 10)
                self.handle_scroll()
            elif key == curses.KEY_NPAGE:  # Page Down
                self.current_row = min(len(self.endpoints) - 1, self.current_row + 10)
                self.handle_scroll()
            elif key == curses.KEY_HOME:
                self.current_row = 0
                self.scroll_offset = 0
            elif key == curses.KEY_END:
                self.current_row = len(self.endpoints) - 1
                self.handle_scroll()

def main(stdscr):
    try:
        viewer = EndpointViewer(stdscr)
        viewer.run()
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    curses.wrapper(main)