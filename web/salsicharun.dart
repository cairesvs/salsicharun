library salsicharun;

import 'dart:html';
import 'dart:math' as Math;
import 'dart:web_gl' as WebGL;
import 'dart:typed_data';
import 'package:vector_math/vector_math.dart';

part 'shader.dart';

WebGL.RenderingContext gl;

class Texture{
	static List<Texture> _pendingTextures = new List<Texture>();
	String url;
	WebGL.Texture texture;
	int width, height;
	bool loaded = false;

	Texture(this.url){
		if(gl==null){
			_pendingTextures.add(this);
		}else{
			_load();
		}
	}

	static void loadAll(){
		_pendingTextures.forEach( (e)=>e._load() );
		_pendingTextures.clear();
	}

	void _load(){
		ImageElement image = new ImageElement();
  	this.texture = gl.createTexture();
		image.onLoad.listen((e){
			gl.bindTexture(WebGL.TEXTURE_2D, texture);
			gl.texImage2D(WebGL.TEXTURE_2D, 0, WebGL.RGBA, WebGL.RGBA, WebGL.UNSIGNED_BYTE, image);
			gl.texParameteri(WebGL.TEXTURE_2D, WebGL.TEXTURE_MIN_FILTER, WebGL.NEAREST);
			gl.texParameteri(WebGL.TEXTURE_2D, WebGL.TEXTURE_MAG_FILTER, WebGL.NEAREST);
			width = image.width;
			height = image.height;
			loaded = true;
		});
		image.src = url;
	}
}

class Quad{
	Shader shader;
	int posLocation;
  WebGL.UniformLocation objectTransformLocation, cameraTransformLocation, viewTransformLocation, textureTransformLocation;
  WebGL.UniformLocation colorLocation;
  Texture texture;

	Quad(this.shader){
		posLocation = gl.getAttribLocation(shader.program, "a_pos");

		objectTransformLocation = gl.getUniformLocation(shader.program, "u_objectTransform");
    cameraTransformLocation = gl.getUniformLocation(shader.program, "u_cameraTransform");
    viewTransformLocation = gl.getUniformLocation(shader.program, "u_viewTransform");
    textureTransformLocation = gl.getUniformLocation(shader.program, "u_textureTransform");
    colorLocation = gl.getUniformLocation(shader.program, "u_color");

  	Float32List vertexArray = new Float32List(4*3);
    vertexArray.setAll(0*3, [0.0, 0.0, 0.0]);
    vertexArray.setAll(1*3, [0.0, 1.0, 0.0]);
    vertexArray.setAll(2*3, [1.0, 1.0, 0.0]);
    vertexArray.setAll(3*3, [1.0, 0.0, 0.0]);

    Int16List indexArray = new Int16List(6);
    indexArray.setAll(0, [0, 1, 2, 0, 2, 3]);

    gl.useProgram(shader.program);
    gl.enableVertexAttribArray(posLocation);
    WebGL.Buffer vertexBuffer = gl.createBuffer();
    gl.bindBuffer(WebGL.ARRAY_BUFFER, vertexBuffer);
    gl.bufferDataTyped(WebGL.ARRAY_BUFFER, vertexArray, WebGL.STATIC_DRAW);
    gl.vertexAttribPointer(posLocation, 3, WebGL.FLOAT, false, 0, 0);

    WebGL.Buffer indexBuffer = gl.createBuffer();
	  gl.bindBuffer(WebGL.ELEMENT_ARRAY_BUFFER, indexBuffer);
	  gl.bufferDataTyped(WebGL.ELEMENT_ARRAY_BUFFER, indexArray, WebGL.STATIC_DRAW);
	  gl.bindBuffer(WebGL.ELEMENT_ARRAY_BUFFER, indexBuffer);
  }

	void setCamera(Matrix4 viewMatrix, Matrix4 cameraMatrix){
		gl.uniformMatrix4fv(viewTransformLocation, false, viewMatrix.storage);
		gl.uniformMatrix4fv(cameraTransformLocation, false, cameraMatrix.storage);
	}

	Matrix4 objectMatrix = new Matrix4.identity();
	Matrix4 textureMatrix = new Matrix4.identity();

	void renderBillboard(Vector3 pos, int w, int h, int uo, int vo, Vector4 color){
		if(!this.texture.loaded) return;

		objectMatrix.setIdentity();
		objectMatrix.translate(pos.x-w/2.0, pos.y-h*1.0, pos.z);
		objectMatrix.scale(w*1.0, h*1.0, 0.0);
		gl.uniformMatrix4fv(objectTransformLocation, false, objectMatrix.storage);

		textureMatrix.setIdentity();
    textureMatrix.scale(1.0/texture.width, 1.0/texture.height, 0.0);
    textureMatrix.translate((uo+0.25), (vo+0.25), 0.0);
    textureMatrix.scale((w-0.5), (h-0.5), 0.0);
		gl.uniformMatrix4fv(textureTransformLocation, false, textureMatrix.storage);

		gl.uniform4fv(colorLocation, color.storage);
		gl.drawElements(WebGL.TRIANGLES, 6, WebGL.UNSIGNED_SHORT, 0);
	}

	void render(Vector3 pos, int w, int h, int uo, int vo, Vector4 color){
  		if(!this.texture.loaded) return;

  		objectMatrix.setIdentity();
  		objectMatrix.translate(pos.x-w, pos.y-h, pos.z);
  		objectMatrix.scale(w*1.0, h*1.0, 0.0);
  		gl.uniformMatrix4fv(objectTransformLocation, false, objectMatrix.storage);

  		textureMatrix.setIdentity();
  		textureMatrix.scale(1.0/texture.width, 1.0/texture.height, 0.0);
  		textureMatrix.translate(uo*1.0, vo*1.0, -1.0);
  		textureMatrix.scale(w*1.0, h*1.0, 0.0);
  		gl.uniformMatrix4fv(textureTransformLocation, false, textureMatrix.storage);

  		gl.uniform4fv(colorLocation, color.storage);
  		gl.drawElements(WebGL.TRIANGLES, 6, WebGL.UNSIGNED_SHORT, 0);
  	}


  void setTexture(Texture texture) {
  	this.texture = texture;
  	gl.bindTexture(WebGL.TEXTURE_2D, texture.texture);
  }
}

class Game {
	CanvasElement canvas;
	Math.Random random;
	Quad quad;
	Texture spriteTexture = new Texture("assets/sprite.png");
	Texture groundTexture = new Texture("assets/ground.png");
	List<bool> keysDown = new List<bool>(256);
  List<bool> keysPressed = new List<bool>(256);

	double fov = 70.0;

	List<Vector3> zombiesPositions = new List<Vector3>();

	void start() {
		keysDown.fillRange(0, keysDown.length, false);
    keysPressed.fillRange(0, keysPressed.length, false);
		random = new Math.Random();
		canvas = querySelector("#game_canvas");
		gl = canvas.getContext("webgl");
		if (gl == null) {
			gl = canvas.getContext("experimental-webgl");
		}
		if (gl == null) {
			crashNoWebGL();
			return;
		}
		gl.enable(WebGL.DEPTH_TEST);
		gl.depthFunc(WebGL.LESS);
		for(int i = 0; i< 100; i++){
			double x = (random.nextDouble()-0.5)*512;
			double z = (random.nextDouble()-0.5)*512;
			zombiesPositions.add(new Vector3(x, 0.0, z));
		}

		window.onKeyDown.listen(onKeyDown);
		window.onKeyUp.listen(onKeyUp);

		quad = new Quad(quadShader);
		Texture.loadAll();
		window.requestAnimationFrame(animate);

	}

  void onKeyDown(KeyboardEvent e) {
    if (e.keyCode<keysDown.length) {
        keysDown[e.keyCode]=true;
    }
  }

  void onKeyUp(KeyboardEvent e) {
    if (e.keyCode<keysDown.length) keysDown[e.keyCode]=false;
  }

	int lastTime = new DateTime.now().millisecondsSinceEpoch;
	double unprocessedFrames = 0.0;

	void animate(double time){
		int now = new DateTime.now().millisecondsSinceEpoch;
		unprocessedFrames+=(now-lastTime)*60/1000.0;
		if (unprocessedFrames>10.0) unprocessedFrames = 10.0;
		while(unprocessedFrames>1.0){
			tick();
			unprocessedFrames-=1.0;
		}
		render();
	}

	void tick(){
		if(keysDown[87]){
			print("caoires");
		}
		if(keysDown[65]){

		}
		if(keysDown[83]){

		}
		if(keysDown[68]){

		}
	}

	void render(){
		gl.viewport(0, 0, canvas.width, canvas.height);
		gl.clearColor(0.2, 0.2, 0.2, 1.0);
		gl.clear(WebGL.COLOR_BUFFER_BIT);
		double pixelScale = 2.0;

		Matrix4 viewMatrix = makePerspectiveMatrix(fov*Math.PI/180, canvas.width/canvas.height, 0.01, 2.0);
		double scale = pixelScale*2.0/canvas.height;
		Matrix4 screenMatrix = new Matrix4.identity().scale(scale,-scale, scale);
		Matrix4 cameraMatrix = new Matrix4.identity().translate(0.0,32.0,-50.0).rotateY(new DateTime.now().millisecondsSinceEpoch%100000/100000.0*Math.PI*2);
		Matrix4 floorCameraMatrix = new Matrix4.identity().rotateX(Math.PI/2.0);

		Vector4 whiteColor = new Vector4(1.0, 1.0, 1.0, 1.0);

		quad.setCamera(viewMatrix, screenMatrix*cameraMatrix*floorCameraMatrix);
		quad.setTexture(groundTexture);
		for(int x=-1; x<=1;x++){
			for(int y=-1; y<=1;y++){
				quad.render(new Vector3(x*256.0, y*256.0, 0.0), 256, 256, 0,0, whiteColor);
			}
		}

		quad.setTexture(spriteTexture);
		quad.setCamera(viewMatrix, screenMatrix);
		for(int i = 0; i<zombiesPositions.length;i++){
			quad.renderBillboard(cameraMatrix*zombiesPositions[i], 16, 16, 32,0, whiteColor);
		}

		quad.renderBillboard(cameraMatrix*new Vector3(0.0,0.0,0.0), 16, 16, 0,0, whiteColor);

		window.requestAnimationFrame(animate);
	}
}

void crashNoWebGL() {
	querySelector("#game_canvas").remove();
	final NodeValidatorBuilder _htmlValidator = new NodeValidatorBuilder.common()..allowElement('a', attributes: ['href']);
	querySelector("#error_log").setInnerHtml('<pre>No WebGL support detected.\rPlease see <a href="http://get.webgl.org/">get.webgl.org</a>.</pre>', validator: _htmlValidator);
}

void main() {
	new Game().start();
}
