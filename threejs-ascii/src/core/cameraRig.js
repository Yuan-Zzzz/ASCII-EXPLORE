import * as THREE from 'three';

// 等距正交相机：固定 45° 偏航 / 35.26° 俯仰，平滑跟随并吸附到字符网格以减少字符抖动
export class CameraRig {
  constructor(frustumHeight = 20) {
    this.frustumHeight = frustumHeight;
    this.camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 1, 120);
    this.offset = new THREE.Vector3(1, 1, 1).normalize().multiplyScalar(45);
    this.camera.position.copy(this.offset);
    this.camera.lookAt(0, 0, 0);
    this.camera.updateMatrixWorld();

    this.right = new THREE.Vector3().setFromMatrixColumn(this.camera.matrixWorld, 0);
    this.up = new THREE.Vector3().setFromMatrixColumn(this.camera.matrixWorld, 1);
    this.forward = new THREE.Vector3().setFromMatrixColumn(this.camera.matrixWorld, 2);

    this.target = new THREE.Vector3();
    this.zoomTarget = 1;
    this.snapped = new THREE.Vector3();
  }

  resize(aspect) {
    const h = this.frustumHeight / 2;
    this.camera.left = -h * aspect;
    this.camera.right = h * aspect;
    this.camera.top = h;
    this.camera.bottom = -h;
    this.camera.updateProjectionMatrix();
  }

  zoomBy(factor) {
    this.zoomTarget = THREE.MathUtils.clamp(this.zoomTarget * factor, 0.6, 2.4);
  }

  // cellWorld：一个字符格对应的世界尺寸，<=0 表示不吸附
  update(dt, focus, cellWorld, snapToFocus = false) {
    if (snapToFocus) this.target.copy(focus);
    else this.target.lerp(focus, 1 - Math.exp(-dt * 4));

    const cam = this.camera;
    if (Math.abs(cam.zoom - this.zoomTarget) > 1e-4) {
      cam.zoom += (this.zoomTarget - cam.zoom) * (1 - Math.exp(-dt * 8));
      cam.updateProjectionMatrix();
    }

    const pr = this.target.dot(this.right);
    const pu = this.target.dot(this.up);
    const pf = this.target.dot(this.forward);
    const snap = (v) => (cellWorld > 0 ? Math.round(v / cellWorld) * cellWorld : v);
    this.snapped
      .copy(this.right)
      .multiplyScalar(snap(pr))
      .addScaledVector(this.up, snap(pu))
      .addScaledVector(this.forward, pf);
    cam.position.copy(this.snapped).add(this.offset);
  }

  // 当前一个世界单位对应多少屏幕像素（用于点精灵尺寸）
  pxPerUnit(viewportHeightPx) {
    return (viewportHeightPx / this.frustumHeight) * this.camera.zoom;
  }
}
