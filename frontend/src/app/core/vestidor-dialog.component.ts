import { ChangeDetectionStrategy, Component, ElementRef, OnDestroy, OnInit, ViewChild, inject, input, output, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { MatButtonModule } from '@angular/material/button';
import { MatIconModule } from '@angular/material/icon';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';
import { firstValueFrom } from 'rxjs';

import { VestidorService } from './vestidor.service';
import { Producto } from '../models/catalogo';

@Component({
  selector: 'app-vestidor-dialog',
  standalone: true,
  imports: [CommonModule, MatButtonModule, MatIconModule, MatProgressSpinnerModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="overlay" (click)="cerrar()">
      <div class="panel" (click)="$event.stopPropagation()">
        <header>
          <h2>Probador virtual</h2>
          <button mat-icon-button type="button" (click)="cerrar()" aria-label="Cerrar">
            <mat-icon>close</mat-icon>
          </button>
        </header>

        <div class="lienzo">
          @if (resultado()) {
            <img class="cara" [src]="resultado()" alt="Foto con la prenda puesta" />
          } @else if (foto()) {
            <img class="cara" [src]="preview()" alt="Tu foto" />
          } @else {
            <video #video autoplay playsinline muted></video>
          }

          @if (cargando()) {
            <div class="capa centro">
              <mat-spinner diameter="48" />
              <p>Poniendo la prenda sobre tu foto…</p>
              <small>Puede tardar unos segundos.</small>
            </div>
          }

          @if (error() && !cargando()) {
            <div class="capa centro error">
              <mat-icon>error_outline</mat-icon>
              <p>{{ error() }}</p>
              <button mat-stroked-button type="button" (click)="error.set(null)">Entendido</button>
            </div>
          }

          @if (camaraError() && !foto() && !resultado() && !cargando() && !error()) {
            <div class="capa centro">
              <mat-icon>videocam_off</mat-icon>
              <p>{{ camaraError() }}</p>
              <p>Igual podés probar subiendo una foto.</p>
              <button mat-stroked-button type="button" (click)="abrirArchivo()">
                <mat-icon>photo_library</mat-icon> Subir foto
              </button>
            </div>
          }
        </div>

        <footer>
          <span class="pie">{{ producto()?.nombre }}</span>
          <div class="acciones">
            @if (resultado()) {
              <button mat-stroked-button type="button" (click)="repetir()">
                <mat-icon>replay</mat-icon> Repetir
              </button>
              <button mat-flat-button type="button" (click)="cerrar()">Cerrar</button>
            } @else if (cargando()) {
              <button mat-stroked-button type="button" (click)="cerrar()">Cancelar</button>
            } @else if (foto()) {
              <button mat-stroked-button type="button" (click)="tomarFoto()">
                <mat-icon>camera_alt</mat-icon> Otra foto
              </button>
              <button mat-stroked-button type="button" (click)="abrirArchivo()">
                <mat-icon>photo_library</mat-icon> Subir foto
              </button>
              <button mat-flat-button type="button" (click)="probar()">
                <mat-icon>checkroom</mat-icon> Probar esta prenda
              </button>
            } @else {
              <small class="hint">Encuadra el torso (o piernas completas para pantalones y faldas).</small>
              <button mat-stroked-button type="button" (click)="abrirArchivo()">
                <mat-icon>photo_library</mat-icon> Subir foto
              </button>
              <button mat-flat-button type="button" (click)="tomarFoto()">
                <mat-icon>camera_alt</mat-icon> Tomar foto
              </button>
            }
          </div>
        </footer>

        <input
          #archivo
          class="sr-only"
          type="file"
          accept="image/jpeg,image/png,image/webp"
          (change)="onArchivo($event)"
        />
      </div>
    </div>
  `,
  styles: [
    `
      .overlay {
        position: fixed;
        inset: 0;
        background: rgba(0, 0, 0, 0.72);
        display: flex;
        align-items: center;
        justify-content: center;
        z-index: 1000;
      }
      .panel {
        background: #14121a;
        color: #fff;
        border-radius: 14px;
        width: min(520px, 94vw);
        max-height: 94vh;
        overflow: hidden;
        display: flex;
        flex-direction: column;
      }
      header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 12px 8px 12px 18px;
        flex: none;
      }
      header h2 {
        margin: 0;
        font-size: 1.05rem;
        font-weight: 600;
      }
      .lienzo {
        position: relative;
        background: #000;
        aspect-ratio: 3 / 4;
        margin: 0 auto;
        width: 100%;
        display: flex;
        align-items: center;
        justify-content: center;
        overflow: hidden;
      }
      video,
      .cara {
        width: 100%;
        height: 100%;
        object-fit: contain;
      }
      video {
        object-fit: cover;
        transform: scaleX(-1);
      }
      .capa {
        position: absolute;
        inset: 0;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 10px;
        text-align: center;
        padding: 16px;
        background: rgba(0, 0, 0, 0.55);
      }
      .capa p {
        margin: 0;
        max-width: 40ch;
        line-height: 1.5;
      }
      .capa mat-icon {
        font-size: 42px;
        width: 42px;
        height: 42px;
      }
      .error mat-icon {
        color: #ef5350;
      }
      footer {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        padding: 12px 18px;
        flex-wrap: wrap;
      }
      .pie,
      .hint {
        opacity: 0.75;
        font-size: 0.85rem;
      }
      .acciones {
        display: flex;
        align-items: center;
        gap: 8px;
        flex-wrap: wrap;
      }
      .sr-only {
        position: absolute;
        width: 1px;
        height: 1px;
        overflow: hidden;
        clip: rect(0 0 0 0);
      }
    `,
  ],
})
export class VestidorDialogComponent implements OnInit, OnDestroy {
  private vestidor = inject(VestidorService);

  readonly producto = input.required<Producto>();
  readonly cerrado = output<void>();

  @ViewChild('video') videoRef?: ElementRef<HTMLVideoElement>;
  @ViewChild('archivo') archivoRef?: ElementRef<HTMLInputElement>;

  readonly foto = signal<Blob | null>(null);
  readonly preview = signal<string | null>(null);
  readonly resultado = signal<string | null>(null);
  readonly cargando = signal(false);
  readonly error = signal<string | null>(null);
  readonly camaraError = signal<string | null>(null);

  private streamLocal: MediaStream | null = null;

  ngOnInit(): void {
    void this.iniciarCamara();
  }

  cerrar(): void {
    this.cerrado.emit();
  }

  ngOnDestroy(): void {
    this.streamLocal?.getTracks().forEach((t) => t.stop());
    this.streamLocal = null;
    this.liberarURL(this.preview());
    this.liberarURL(this.resultado());
  }

  /** Toma una foto desde el preview de la cámara y la deja lista para probar. */
  async tomarFoto(): Promise<void> {
    const video = this.videoRef?.nativeElement;
    if (!video || video.videoWidth === 0 || video.videoHeight === 0) {
      this.error.set('La cámara todavía no muestra imagen. Esperá un segundo y volvé a intentar.');
      return;
    }
    this.error.set(null);
    const w = video.videoWidth;
    const h = video.videoHeight;
    const canvas = document.createElement('canvas');
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext('2d');
    if (!ctx) {
      this.error.set('No se pudo capturar la foto.');
      return;
    }
    // Espejado igual que el preview, para que coincida con lo que vio el usuario.
    ctx.translate(w, 0);
    ctx.scale(-1, 1);
    ctx.drawImage(video, 0, 0, w, h);
    const blob = await new Promise<Blob | null>((resolve) =>
      canvas.toBlob(resolve, 'image/jpeg', 0.9),
    );
    if (blob) this.fijarFoto(blob);
  }

  abrirArchivo(): void {
    this.archivoRef?.nativeElement.click();
  }

  onArchivo(event: Event): void {
    const input = event.target as HTMLInputElement;
    const archivo = input.files?.[0];
    input.value = '';
    if (!archivo) return;
    this.fijarFoto(archivo);
  }

  /** Manda la foto al backend; si sale bien se muestra el resultado. */
  async probar(): Promise<void> {
    const producto = this.producto();
    const foto = this.foto();
    if (!producto || !foto) return;
    this.error.set(null);
    this.cargando.set(true);
    try {
      const blob = await firstValueFrom(this.vestidor.probar(producto, foto));
      this.liberarURL(this.resultado());
      this.resultado.set(URL.createObjectURL(blob));
    } catch (e) {
      this.error.set(await this.vestidor.mensajeDeError(e));
    } finally {
      this.cargando.set(false);
    }
  }

  /** Vuelve al estado de captura para tomar otra foto. */
  repetir(): void {
    this.liberarURL(this.resultado());
    this.liberarURL(this.preview());
    this.resultado.set(null);
    this.foto.set(null);
    this.preview.set(null);
    this.error.set(null);
  }

  private fijarFoto(blob: Blob): void {
    this.liberarURL(this.preview());
    this.preview.set(URL.createObjectURL(blob));
    this.foto.set(blob);
    this.error.set(null);
  }

  private liberarURL(url: string | null): void {
    if (url) {
      try {
        URL.revokeObjectURL(url);
      } catch {
        // ya liberada
      }
    }
  }

  private async iniciarCamara(): Promise<void> {
    if (!navigator.mediaDevices?.getUserMedia) {
      this.camaraError.set('Este navegador no permite usar la cámara.');
      return;
    }
    if (!window.isSecureContext) {
      this.camaraError.set('La cámara necesita una conexión segura (https).');
      return;
    }
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'user' },
        audio: false,
      });
      this.streamLocal?.getTracks().forEach((t) => t.stop());
      this.streamLocal = stream;
      const video = this.videoRef?.nativeElement;
      if (video) {
        video.srcObject = stream;
        await video.play();
      }
    } catch (e) {
      this.camaraError.set(this.mensajeDeCamara(e));
    }
  }

  private mensajeDeCamara(e: unknown): string {
    const nombre = e instanceof DOMException ? e.name : '';
    if (nombre === 'NotAllowedError') {
      return 'Permiso de cámara denegado. Habilitalo en el candado de la barra de direcciones.';
    }
    if (nombre === 'NotFoundError' || nombre === 'OverconstrainedError') {
      return 'No se encontró una cámara disponible.';
    }
    return 'No se pudo abrir la cámara.';
  }
}