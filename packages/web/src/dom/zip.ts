const table = Uint32Array.from({ length: 256 }, (_, index) => {
	let value = index;
	for (let bit = 0; bit < 8; bit++) value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
	return value >>> 0;
});

function crc32(bytes: Uint8Array) {
	let crc = 0xffffffff;
	for (const byte of bytes) crc = table[(crc ^ byte) & 0xff]! ^ (crc >>> 8);
	return (crc ^ 0xffffffff) >>> 0;
}

/** A ZIP archive of the files, stored without compression. A PNG is already compressed, and the JSON is small. */
export function zip(files: { name: string; bytes: Uint8Array }[]): Blob {
	const encoder = new TextEncoder();
	const parts: Uint8Array[] = [];
	const directory: Uint8Array[] = [];
	let offset = 0;
	for (const file of files) {
		const name = encoder.encode(file.name);
		const crc = crc32(file.bytes);
		const header = new DataView(new ArrayBuffer(30));
		header.setUint32(0, 0x04034b50, true);
		header.setUint16(4, 20, true);
		header.setUint16(6, 0x0800, true);
		header.setUint32(14, crc, true);
		header.setUint32(18, file.bytes.length, true);
		header.setUint32(22, file.bytes.length, true);
		header.setUint16(26, name.length, true);
		const entry = new DataView(new ArrayBuffer(46));
		entry.setUint32(0, 0x02014b50, true);
		entry.setUint16(4, 20, true);
		entry.setUint16(6, 20, true);
		entry.setUint16(8, 0x0800, true);
		entry.setUint32(16, crc, true);
		entry.setUint32(20, file.bytes.length, true);
		entry.setUint32(24, file.bytes.length, true);
		entry.setUint16(28, name.length, true);
		entry.setUint32(42, offset, true);
		parts.push(new Uint8Array(header.buffer), name, file.bytes);
		directory.push(new Uint8Array(entry.buffer), name);
		offset += 30 + name.length + file.bytes.length;
	}
	const directorySize = directory.reduce((sum, part) => sum + part.length, 0);
	const end = new DataView(new ArrayBuffer(22));
	end.setUint32(0, 0x06054b50, true);
	end.setUint16(8, files.length, true);
	end.setUint16(10, files.length, true);
	end.setUint32(12, directorySize, true);
	end.setUint32(16, offset, true);
	return new Blob([...parts, ...directory, new Uint8Array(end.buffer)] as BlobPart[], { type: 'application/zip' });
}
