// The map's relief: terrain heights at 0.05° (about 5.5 km) in the climate's
// 10° squares (data/forkcast_data/relief.py), fetched only while the Relief
// layer is on.

/** out/relief.json */
export interface ReliefHeader {
  /** Degrees between heights */
  step: number;
  /** Degrees a tile spans */
  tile: number;
  /** Heights along each side of a tile, its edges included */
  size: number;
  /** The tiles there are, by their south-west corner ("<lat>_<lon>") */
  tiles: string[];
}

/** One tile's heights, `size` × `size` from its north-west corner. */
export class ReliefTile {
  readonly lat0: number;
  readonly lon0: number;
  readonly step: number;
  readonly rows: number;
  readonly cols: number;
  readonly #heights: Int16Array;

  constructor(header: ReliefHeader, id: string, buffer: ArrayBuffer) {
    const [lat, lon] = id.split('_').map(Number) as [number, number];
    this.lat0 = lat + header.tile;
    this.lon0 = lon;
    this.step = header.step;
    this.rows = this.cols = header.size;
    // Little-endian int16, which is what every browser's Int16Array reads.
    this.#heights = new Int16Array(buffer);
  }

  /** Height in metres (NaN outside the tile). */
  height(row: number, col: number): number {
    return row < 0 || col < 0 || row >= this.rows || col >= this.cols
      ? Number.NaN
      : this.#heights[row * this.cols + col]!;
  }
}
