module Ladb::OpenCutList

  require 'json'

  # MCFT — the estimate, on screen and printable.
  #
  # A gauge, not a quotation: Amit, 2026-08-22, "its just a gauge to see me if
  # client makes sense for this budget". So it is deliberately plain, it prints
  # from the browser with Cmd-P, and it says on its face what it excludes.
  #
  # EVERY NUMBER CARRIES ITS ORIGIN. That is the requirement, not decoration:
  # "i should clearly know from where cost data is coming erp or plugin as
  # plugin also have capability to store material cost data." The plugin does
  # hold its own std_prices — and this screen consults none of them. A line
  # ERP could not price is shown, marked, and LEFT OUT of the total, with the
  # count of such lines beside the total so a missing board cannot hide inside
  # a plausible number.
  module McftEstimateDialog

    def self.show(data)
      dlg = UI::HtmlDialog.new(
        :dialog_title => 'MCFT — Estimate (ERP priced)',
        :preferences_key => 'ladb_opencutlist_mcft_estimate',
        :scrollable => true, :resizable => true,
        :width => 900, :height => 720, :style => UI::HtmlDialog::STYLE_DIALOG,
      )
      dlg.set_html(_html(data))
      dlg.center
      dlg.show
      dlg
    end

    def self._esc(s)
      s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
    end

    def self._money(v)
      # Grouped Indian-style at the lakh, because that is how the number will
      # be read aloud to the person sitting next to you.
      whole = format('%.2f', v.to_f)
      int, dec = whole.split('.')
      neg = int.start_with?('-')
      int = int.sub('-', '')
      if int.length > 3
        head, tail = int[0...-3], int[-3..-1]
        head = head.reverse.scan(/\d{1,2}/).join(',').reverse
        int = "#{head},#{tail}"
      end
      "#{neg ? '-' : ''}#{int}.#{dec}"
    end

    # ERP source strings -> a short badge and whether it is a warning.
    def self._badge(src)
      s = src.to_s
      return ['NOT IN ERP', true] if s == 'not in erp'
      return ['ERP assumed', false] if s.end_with?('assumed')
      return ['ERP unset', true] if s.end_with?('unset')
      return ['edited here', true] if s.start_with?('plugin')
      return ['seed default', true] if s == 'code default'
      [s.sub('erp:', 'ERP '), false]
    end

    def self._rows(list, cols)
      list.map { |r|
        '<tr>' + cols.map { |c| c.call(r) }.join + '</tr>'
      }.join
    end

    def self._html(d)
      mats = d['materials'] || []
      lab  = d['labour'] || []
      unpriced = (d['unpriced_lines'] || 0).to_i

      mat_rows = _rows(mats, [
        ->(r) { "<td>#{_esc(r['code'])}</td>" },
        ->(r) { "<td class='n'>#{r['qty']}</td>" },
        ->(r) { "<td>#{_esc(r['uom'])}</td>" },
        ->(r) { "<td class='n'>#{_money(r['rate'])}</td>" },
        ->(r) { "<td class='n'>#{r['quotable'] ? _money(r['amount']) : '—'}</td>" },
        ->(r) { b, warn = _badge(r['source'])
                "<td><span class='b#{warn ? ' w' : ''}'>#{_esc(b)}</span></td>" },
      ])

      lab_rows = _rows(lab, [
        ->(r) { "<td>#{r['seq']}. #{_esc(r['name'])}</td>" },
        ->(r) { "<td class='ws'>#{_esc(r['workstation'])}</td>" },
        ->(r) { "<td class='n'>#{r['qty']}</td>" },
        ->(r) { "<td class='n'>#{r['min_per_unit']}</td>" },
        ->(r) { "<td class='n'>#{r['hours']}</td>" },
        ->(r) { "<td class='n'>#{_money(r['hour_rate'])}</td>" },
        ->(r) { "<td class='n'>#{_money(r['amount'])}</td>" },
        ->(r) { b, warn = _badge(r['min_source'])
                "<td><span class='b#{warn ? ' w' : ''}'>#{_esc(b)}</span></td>" },
      ])

      warn_html = ''
      if unpriced > 0
        warn_html = "<p class='alert'><b>#{unpriced} material line" \
                    "#{unpriced == 1 ? '' : 's'} not priced in ERP</b> — shown " \
                    "above and EXCLUDED from the total. Set a rate on the " \
                    "#{_esc(d['price_list'])} price list and run this again.</p>"
      end
      made = (d['created_items'] || [])
      if made.any?
        warn_html += "<p class='alert'>#{made.length} new material" \
                     "#{made.length == 1 ? '' : 's'} were added to ERP by this " \
                     "run and still need a rate: #{_esc(made.join(', '))}</p>"
      end

      <<~HTML
        <!DOCTYPE html><html><head><meta charset="utf-8"><style>
          body { font: 13px/1.45 -apple-system, "Segoe UI", Roboto, sans-serif;
                 margin: 22px; color: #16181c; }
          h1 { font-size: 17px; margin: 0 0 2px; }
          h2 { font-size: 13px; text-transform: uppercase; letter-spacing: .06em;
               color: #6b7280; margin: 22px 0 6px; }
          .sub { color: #6b7280; font-size: 12px; margin: 0 0 4px; }
          table { border-collapse: collapse; width: 100%; }
          th, td { text-align: left; padding: 5px 8px;
                   border-bottom: 1px solid #e6e8eb; vertical-align: top; }
          th { font-size: 11px; text-transform: uppercase; letter-spacing: .04em;
               color: #6b7280; border-bottom: 1px solid #c9ccd1; }
          td.n, th.n { text-align: right; font-variant-numeric: tabular-nums; }
          td.ws { color: #6b7280; }
          .b { font-size: 10px; padding: 1px 6px; border-radius: 9px;
               background: #eef2f6; color: #46506a; white-space: nowrap; }
          .b.w { background: #fdecec; color: #922; }
          .alert { background: #fdecec; border-left: 3px solid #c33;
                   padding: 8px 12px; margin: 12px 0; }
          .tot { margin-top: 18px; border-top: 2px solid #16181c; padding-top: 10px; }
          .tot table { width: auto; margin-left: auto; }
          .tot td { border: 0; padding: 3px 10px; }
          .grand { font-size: 17px; font-weight: 700; }
          .foot { margin-top: 20px; color: #6b7280; font-size: 11px;
                  border-top: 1px solid #e6e8eb; padding-top: 10px; }
          @media print { body { margin: 0; } .noprint { display: none; } }
        </style></head><body>

        <h1>Estimate — indicative</h1>
        <p class="sub">Priced by ERPNext (#{_esc(d['site'])}) from
           #{_esc(d['price_list'])}, #{_esc(d['rates_are'])}.
           #{_esc(d['as_of'])}</p>
        <p class="sub">#{d['parts']} part rows · #{d['panels']} panels ·
           #{d['assembly_count']} assemblies
           (#{_esc(d['assembly_source'])}) · wastage: #{_esc(d['wastage'])}</p>

        #{warn_html}

        <h2>Material</h2>
        <table><thead><tr>
          <th>Item</th><th class="n">Qty</th><th>UOM</th>
          <th class="n">Rate</th><th class="n">Amount</th><th>Source</th>
        </tr></thead><tbody>#{mat_rows}</tbody></table>

        <h2>Labour — the 17 steps, pasting to installation</h2>
        <table><thead><tr>
          <th>Operation</th><th>Workstation</th><th class="n">Qty</th>
          <th class="n">Min/unit</th><th class="n">Hours</th>
          <th class="n">₹/hr</th><th class="n">Amount</th><th>Std time</th>
        </tr></thead><tbody>#{lab_rows}</tbody></table>

        <div class="tot"><table>
          <tr><td>Material</td><td class="n">#{_money(d['material_total'])}</td></tr>
          <tr><td>Labour</td><td class="n">#{_money(d['labour_total'])}</td></tr>
          <tr class="grand"><td>Total</td><td class="n">#{_money(d['total'])}</td></tr>
        </table></div>

        <p class="foot">
          A GAUGE, not a quotation. Excludes: #{_esc((d['excludes'] || []).join(', '))}.
          Every rate here comes from ERPNext — the plugin's own material prices
          are not used. Print with Ctrl/Cmd-P.
        </p>
        </body></html>
      HTML
    end
  end
end
