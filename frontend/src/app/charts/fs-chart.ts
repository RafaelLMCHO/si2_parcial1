import {
  Component,
  ElementRef,
  Input,
  OnChanges,
  OnDestroy,
  OnInit,
  SimpleChanges,
  ViewChild,
  inject,
} from '@angular/core';
import { CommonModule } from '@angular/common';
import {
  Chart,
  ChartConfiguration,
  ChartData,
  ChartType,
  registerables,
} from 'chart.js';

Chart.register(...registerables);

@Component({
  selector: 'app-fs-chart',
  templateUrl: './fs-chart.html',
  styleUrl: './fs-chart.scss',
  standalone: true,
  imports: [CommonModule],
})
export class FsChartComponent implements OnInit, OnChanges, OnDestroy {
  private host = inject(ElementRef);

  @ViewChild('canvas', { static: true }) canvasRef!: ElementRef<HTMLCanvasElement>;

  @Input() type: ChartType = 'bar';
  @Input() labels: string[] = [];
  @Input() datasets: { label?: string; data: number[]; backgroundColor?: string[]; borderColor?: string[] }[] = [];
  @Input() tooltipPrefix = '';
  @Input() horizontal = false;
  @Input() stacked = false;

  private chart?: Chart;

  ngOnInit(): void {
    this.crear();
  }

  ngOnChanges(changes: SimpleChanges): void {
    if (!this.chart) return;
    if (changes['type']) {
      this.chart.destroy();
      this.crear();
      return;
    }
    this.chart.data.labels = this.labels;
    this.chart.data.datasets = this.datasets as ChartData['datasets'];
    this.chart.update();
  }

  private crear(): void {
    const ctx = this.canvasRef.nativeElement.getContext('2d');
    if (!ctx) return;

    const config: ChartConfiguration = {
      type: this.type,
      data: {
        labels: this.labels,
        datasets: (this.datasets as ChartData['datasets']).map((d) => ({
          ...d,
          borderRadius: 6,
        })),
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        indexAxis: this.horizontal ? 'y' : 'x',
        plugins: {
          legend: { display: this.datasets.length > 1, position: 'bottom' },
          tooltip: {
            callbacks: {
              label: (ctx) =>
                `${ctx.dataset.label ?? ''}: ${this.tooltipPrefix}${ctx.parsed.y ?? ctx.parsed.x}`,
            },
          },
        },
      },
    };
    this.chart = new Chart(ctx, config);
  }

  ngOnDestroy(): void {
    this.chart?.destroy();
  }
}